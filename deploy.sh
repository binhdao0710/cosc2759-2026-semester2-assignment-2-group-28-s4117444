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
BACKEND_PUBLIC_IP=$(terraform output -raw backend_public_ip)
FRONTEND_PUBLIC_IP=$(terraform output -raw frontend_public_ip)
DB_PRIVATE_IP=$(terraform output -raw db_private_ip)
cd .. 
chmod 400 ./terraform/private-posts-key.pem

cat > ansible/inventory.ini <<EOF
[db]
<DB_PUBLIC_IP> ansible_user=ubuntu ansible_ssh_private_key_file=./terraform/private-posts-key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[backend]
<BACKEND_PUBLIC_IP> ansible_user=ubuntu ansible_ssh_private_key_file=./terraform/private-posts-key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[frontend]
<FRONTEND_PUBLIC_IP> ansible_user=ubuntu ansible_ssh_private_key_file=./terraform/private-posts-key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

#wait for SSH to be available for ansible to login 
echo "waiting for SSH on $DB_PUBLIC_IP..."
#-z checks if the port is open and doesn't send any data
#-w5 means the command timeouts after 5 seconds
until nc -z -w5 "$DB_PUBLIC_IP" 22; do 
    sleep 5
    echo "Still waiting..."
done

echo "waiting for SSH on $BACKEND_PUBLIC_IP..."
until nc -z -w5 "$BACKEND_PUBLIC_IP" 22; do 
    sleep 5
    echo "Still waiting..."
done

echo "waiting for SSH on $FRONTEND_PUBLIC_IP..."
until nc -z -w5 "$FRONTEND_PUBLIC_IP" 22; do 
    sleep 5
    echo "Still waiting..."
done

ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  --extra-vars "db_user=$DB_USER db_password=$DB_PASSWORD db_host=$DB_PRIVATE_IP backend_url=http://$BACKEND_PUBLIC_IP:8080"

echo "Deployment complete. Backend available at: http://$BACKEND_PUBLIC_IP:8080. Frontend is available at: http://$FRONTEND_PUBLIC_IP:8081"
curl -sf "http://$IP:8080" && echo "" && echo "Backend responded successfully."
curl -sf "http://$IP:8081" && echo "" && echo "Frontend is available." 