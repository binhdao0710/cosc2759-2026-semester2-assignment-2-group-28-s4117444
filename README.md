# COSC2759 Assignment 2 - Semester 2, 2026

# Services

## Backend

This is the Backend Posts Service. It is responsible for talking to the Posts DB, and exposing an internal HTTP API for managing Posts.

### Environment Variables

| Environment Variable | Purpose                                                 |
| -------------------- | ------------------------------------------------------- |
| PORT                 | Which port will the service listen on for HTTP requests |
| DB_USER              | Username for connecting to the Backend DB               |
| DB_PASSWORD          | Password for connecting to the Backend DB               |
| DB_HOST              | Hostname/Network address for the Backend DB             |

### Image

The Backend service image is available at `liamrmit/sdo-2026:backend`.

### Dependencies

The Backend service depends on a PostgreSQL database, with the required migrations. An image for this has been provided, available at `liamrmit/sdo-2026:db`.

### Database Configuration

The PostgreSQL Databse container also requires some environment variables to be configured.

| Environment Variable | Purpose                                            |
| -------------------- | -------------------------------------------------- |
| POSTGRES_USER        | Username for the Backend Service to use to connect |
| POSTGRES_PASSWORD    | Password for the Backend Service to use to connect |
| POSTGRES_DB          | "posts"                                            |

## Frontend

This is the Frontend Posts Service. It is responsible for serving a UI to users over HTTP. This UI allows them to view and manage Posts.

### Environment Variables

| Environment Variable | Purpose                                                 |
| -------------------- | ------------------------------------------------------- |
| PORT                 | Which port will the service listen on for HTTP requests |
| BACKEND_URL          | Fully qualified URL for reaching the Backend Service    |

### Image

The Frontend service image is available at `liamrmit/sdo-2026:frontend`.

# Running The Services Locally (In Docker)

1. Run `docker compose up -d` to start the two services, and a postgres database container.
2. View the Frontend Posts Service at `http://localhost:8081`, and the Backend Posts Service at `http://localhost:8080`.

# Deploying The Services

The services can be deployed to EC2.

Each container needs:

- The correct environment variables configured (refer to the above sections)
- Security Groups will need to be configured to allow traffic to reach the instances.
  - They will also need to be configured to allow the instances to talk to each other, if the services are deployed on different instances.
  - The PostgreSQL database receives inbound traffic on port `5432`
  - The ports used by the Backend and Frontend services are configurable through the `PORT` environment variable. Otherwise, it will default to port `8081`.

# Automatic Deployment Implementation

## Components

### Terraform (`terraform/`)

- `terraform.tf`: Specify required providers (aws) and required version.
- `main.tf`: Specify environments and resources to be configured, including:
  - Security groups for the application load balancers, the database, the frontend, and the backend.
  - Encryption key pair for access to EC2 instances.
  - An S3 bucket to store the terraform state file.
  - The listeners, target groups, load balancers, and attachments for the frontend and backend.
  - 1 EC2 instance for the database, 2 instances for the frontend, and 2 instances for the backend.
- `outputs.tf`: Exposes the database public and private IPs, the frontend public IPs, the backend public IPs, and the ALB DNS of the frontend and backend for use in `deploy.sh`.

### Ansible (`ansible/`)

- `playbook.yml`: Setup Docker on all 5 EC2 instances, deploy 5 containers, one on each instance, using the provided images. The database is accessible through port 5432, the frontend is accessible through port 8081, and the backend is accessible through port 8080.
- `inventory.ini`: Generated automatically by `deploy.sh` containing the IPs and DNS names retrieved in `output.tf`, along with the location of the private key for SSH connection.

### `deploy.sh`

This is a bash script that fully automates the deployment process.

- The script first checks if the required services (Ansible, Terraform) have been set up.
- It then runs Terraform, sets up the environmental variables and ensure SSH connection is available.
- Once SSH is available, the Ansible inventory is generated, and the playbook is run afterwards.
- DB credentials are prompted interactively as a fallback if not already available.
- AWS credentials are expected as pre-exported environment variables.

### `cd-pipeline.yaml`

The pipeline leverages the deployment script:

- The pipeline triggers on pushes to the main branch.
- The pipeline sets up Terraform and Ansible on a fresh VM instance running Ubuntu.
- The machine then get passed credentials as environmental variables that are needed for `deploy.sh`.
- A permission is added to allow the script to run and then it is executed.

## Design decisions and justifications

- **Port 22 open to 0.0.0.0/0 on all EC2 instances**: The port was opened so that Ansible can connect via SSH to all containers.
- **Port 80 open to 0.0.0.0/0 on the ALB security groups**: The ALB listeners are opened on port 80, load balancers accept public HTTP traffic on that port and forward it to the instances on 8080 (backend) and 8081 (frontend).
- **Port 8080 on backend instances and 8081 on frontend instances open to ALB security group**: These ports are required to be opened as it is how the ALB communicates with these EC2 instances.
- **Port 5432 not exposed to the public**: Port 5432 of the database container is only exposed to the backend, defined in the security group rules. This ensures that the database is not reachable by any ordinary user.
- **Credentials never committed**:AWS and DB credentials are stored as GitHub Actions secrets and passed to the pipeline as environment variables. When deploy.sh is run locally, DB credentials are prompted for interactively if they aren’t already set. No credential is written to a file in the repo. In addition, the `.gitignore` excludes `*.pem`, `*.tfstate*`, and the generated `ansible/inventory.ini`, to ensure no sensitive data is exposed.
- **Terraform state stored remotely in S3**: The state file is stored in an S3 bucket rather than on the machine running Terraform. Because the pipeline runs on a fresh VM each time, a local state file would be lost after every run, and Terraform would try to recreate all resources on the next push. Remote state lets every run, local or CI, see the infrastructure that already exists. It also keeps the state file out of the repo, since it can contain sensitive values (e.g. the private key, if the key pair is generated by Terraform).
