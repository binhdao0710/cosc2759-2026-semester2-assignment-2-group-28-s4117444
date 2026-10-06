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
- `main.tf`: Specify environments and resources to be configured.
- `outputs.tf`: Exposes `instance_public_ip` for use by `deploy.sh`.

### Ansible (`ansible/`)

- `playbook.yml`: Installs Docker, creates the `posts-net` network, install the Docker Python SDK on the containers, starts the `db`, `backend`, and `frontend` containers with the required environment variables.
- `inventory.ini`: Generated automatically by `deploy.sh` containing the public IP address and Ansible SSH credentials.

### `deploy.sh`

This is a bash script that fully automates the deployment process.

- The script first checks if the required services (Ansible, Terraform) has been set up.
- It then runs Terraform and ensure SSH connection is available.
- Once SSH is available, the Ansible inventory is generated, and the playbook is run afterwards.
- DB credentials are prompted interactively and never stored in the repo.
- AWS credentials are expected as pre-exported environment variables.

## Design decisions and justifications

- **Port 22 open to 0.0.0.0/0**: The port was opened so that Ansible can connect via SSH.
- **Port 5432 not exposed**: the Backend and DB containers communicate over a private Docker network on the same host, so no security group rule is needed for Postgres traffic in this section.
- **Credentials never committed**: DB credentials are prompted at runtime and AWS credentials are read from the environment. No credential is written to a file in the repo. In addtion, the `.gitignore` excludes `*.pem`, `*.tfstate*`, and the generated `ansible/inventory.ini`, to ensure no sensitive data is exposed.
