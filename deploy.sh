#!/bin/bash
set -euo pipefail

command -v terraform > /dev/null || { echo "terraform not found"; exit 1; }
command -v ansible > /dev/null ||  { echo "ansible not found"; exit 1; }

: "${AWS_ACCESS_KEY_ID:?Please set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Please set AWS_SECRET_ACCESS_KEY}"
: "${AWS_SESSION_TOKEN:?Please set AWS_SESSION_TOKEN}"

#if DB_USER or USER_PASSWOR has not been set, the ":-" 
#operators set the value as an empty string to prevent
#set -u from crashing 

if [ -z "${DB_USER:-}" ]; then
    read -rp "Enter DB username: " DB_USER
fi

if [ -z "${DB_PASSWORD:-}" ]; then 
    read -rps "Enter DB password: " DB_PASSWORD
fi 
cd terraform
terraform init
terraform apply -auto-approve 
#stops the interactive prompt 

DB_PUBLIC_IP=$(terraform output -raw db_public_ip)
BACKEND_ALB_IP=$(terraform output -raw backend_alb_dns)
FRONTEND_ALB_IP=$(terraform output -raw frontend_alb_dns)
DB_PRIVATE_IP=$(terraform output -raw db_private_ip)
BACKEND_PUBLIC_IPS=$(terraform output -json backend_public_ips | jq -r '.[]')
FRONTEND_PUBLIC_IPS=$(terraform output -json frontend_public_ips | jq -r '.[]')

cd .. 
chmod 400 ./terraform/private-posts-key.pem

cat > ansible/inventory.ini <<EOF
[db]
$DB_PUBLIC_IP

[backend]
$BACKEND_PUBLIC_IPS

[frontend]
$FRONTEND_PUBLIC_IPS

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=./terraform/private-posts-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF


#wait for SSH to be available for ansible to login 
echo "waiting for SSH on $DB_PUBLIC_IP..."
#-z checks if the port is open and doesn't send any data
#-w5 means the command timeouts after 5 seconds
until nc -z -w5 "$DB_PUBLIC_IP" 22; do 
    sleep 5
    echo "Still waiting..."
done

for ip in $BACKEND_PUBLIC_IPS $FRONTEND_PUBLIC_IPS; do
    echo "waiting for SSH on $ip..."
    until nc -z -w5 "$ip" 22; do 
        sleep 5
        echo "Still waiting..."
    done
done

ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  --extra-vars "db_user=$DB_USER db_password=$DB_PASSWORD db_host=$DB_PRIVATE_IP backend_url=http://$BACKEND_ALB_IP"

echo "Deployment complete. Backend available at: http://$BACKEND_ALB_IP. Frontend is available at: http://$FRONTEND_ALB_IP"
curl -sf "http://$BACKEND_ALB_IP" && echo "" && echo "Backend responded successfully."
curl -sf "http://$FRONTEND_ALB_IP" && echo "" && echo "Frontend is available." 