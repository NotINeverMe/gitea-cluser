# Gitea Docker Stack Terraform Module

A comprehensive Terraform module for deploying a production-ready Gitea instance with PostgreSQL, Actions Runner, Caddy reverse proxy, and DevSecOps dashboard using Docker.

## Features

- **Gitea Git Server**: Self-hosted Git service with web UI
- **PostgreSQL Database**: Dedicated database for Gitea
- **Actions Runner**: CI/CD runner for Gitea Actions
- **Caddy Reverse Proxy**: Automatic HTTPS with Let's Encrypt
- **DevSecOps Dashboard**: Monitoring and management interface
- **Security Hardening**: Rootless containers, secure defaults, CMMC compliance labels
- **Network Isolation**: Separate networks for data, default, and monitoring traffic
- **Resource Management**: CPU and memory limits for all containers
- **Evidence Logging**: Automatic compliance evidence generation

## Requirements

- Terraform >= 1.5.0
- Docker Engine >= 20.10
- Docker Compose (optional, for reference)
- 8GB RAM minimum (16GB recommended)
- 20GB disk space minimum

## Quick Start

### 1. Create terraform.tfvars

```hcl
# terraform.tfvars
admin_username = "admin"
admin_password = "SuperSecure123!@#"  # Min 14 chars with upper, lower, digit, special
admin_email    = "admin@example.com"

gitea_domain = "git.example.com"

# Component configuration
enable_runner    = true
enable_caddy     = false  # Set true for production with HTTPS
enable_dashboard = true

# Resource limits
gitea_cpu_limit    = 4
gitea_memory_limit = 4096
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy the stack
terraform apply

# Get admin credentials
terraform output -json admin_credentials_file
```

### 3. Access Services

After deployment, access your services:

- **Gitea Web UI**: http://localhost:10000
- **DevSecOps Dashboard**: http://localhost:8000
- **PostgreSQL**: localhost:10002

## Module Usage

### Basic Configuration

```hcl
module "gitea_stack" {
  source = "./terraform/gitea-stack"

  # Admin credentials
  admin_username = "admin"
  admin_password = var.gitea_admin_password
  admin_email    = "admin@example.com"

  # Domain configuration
  gitea_domain = "git.example.com"

  # Port configuration
  gitea_http_port = 10000
  gitea_ssh_port  = 10001
  postgres_port   = 10002

  # Component toggles
  enable_runner    = true
  enable_caddy     = false
  enable_dashboard = true

  # Resource limits
  gitea_cpu_limit    = 4
  gitea_memory_limit = 4096
  postgres_cpu_limit = 2
  postgres_memory_limit = 2048
}
```

### Advanced Configuration

```hcl
module "gitea_stack" {
  source = "./terraform/gitea-stack"

  # Stack naming
  stack_name = "gitea-prod"

  # Admin configuration
  admin_username = "admin"
  admin_password = var.gitea_admin_password
  admin_email    = "admin@company.com"

  # Domain and URLs
  gitea_domain   = "git.company.com"
  gitea_root_url = "https://git.company.com/"

  # Security tokens (auto-generated if not provided)
  gitea_secret_key        = var.gitea_secret_key
  gitea_internal_token    = var.gitea_internal_token
  gitea_oauth2_jwt_secret = var.gitea_oauth2_jwt_secret

  # Component configuration
  enable_runner    = true
  enable_caddy     = true
  enable_dashboard = true

  # Caddy configuration
  caddyfile_path   = "./config/Caddyfile"
  caddy_https_port = 443
  caddy_http_port  = 80

  # Runner configuration
  runner_config_path = "./config/runner-config.yaml"
  gitea_runner_token = var.runner_token

  # Image versions
  gitea_image    = "gitea/gitea:1.21-rootless"
  postgres_image = "postgres:15-alpine"
  runner_image   = "gitea/act_runner:latest"
  caddy_image    = "caddy:2-alpine"

  # Resource limits
  gitea_cpu_limit       = 4
  gitea_memory_limit    = 4096
  postgres_cpu_limit    = 2
  postgres_memory_limit = 2048
  runner_cpu_limit      = 4
  runner_memory_limit   = 8192

  # Security settings
  gitea_disable_registration = true
  gitea_require_signin_view  = false
  gitea_cookie_secure       = true
  gitea_webhook_skip_tls    = false

  # Rootless configuration
  gitea_rootless = true
  gitea_user_uid = 1000
  gitea_user_gid = 1000

  # Network configuration
  network_subnet_default    = "172.20.0.0/16"
  network_subnet_data      = "172.21.0.0/16"
  network_subnet_monitoring = "172.22.0.0/16"

  # Backup configuration
  backup_path = "/backups/gitea"

  # Additional labels
  additional_labels = {
    environment = "production"
    team        = "platform"
    cost_center = "engineering"
  }
}
```

## Variables Reference

### Required Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `admin_password` | string | Admin password (min 14 chars, complex) | `SuperSecure123!@#` |

### Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `stack_name` | string | `gitea` | Stack identifier for resources |
| `admin_username` | string | `admin` | Admin username |
| `admin_email` | string | `admin@example.com` | Admin email |
| `gitea_domain` | string | `localhost` | Domain for Gitea |
| `gitea_http_port` | number | `10000` | HTTP port |
| `gitea_ssh_port` | number | `10001` | SSH port |
| `postgres_port` | number | `10002` | PostgreSQL port |
| `enable_runner` | bool | `true` | Enable Actions runner |
| `enable_caddy` | bool | `false` | Enable Caddy proxy |
| `enable_dashboard` | bool | `true` | Enable dashboard |
| `gitea_cpu_limit` | number | `4` | CPU limit for Gitea |
| `gitea_memory_limit` | number | `4096` | Memory limit (MB) |
| `gitea_rootless` | bool | `true` | Run in rootless mode |
| `gitea_disable_registration` | bool | `false` | Disable user registration |

## Security Features

### Automatic Token Generation

The module automatically generates secure tokens if not provided:

- **Secret Key**: 64-character session encryption key
- **Internal Token**: 128-character service communication token
- **OAuth2 JWT Secret**: 44-character JWT signing secret
- **Database Password**: 32-character PostgreSQL password
- **Metrics Token**: 32-character Prometheus endpoint token

### Password Requirements

Admin password must meet these requirements:
- Minimum 14 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one digit
- At least one special character

### Network Isolation

- **Default Network**: General communication
- **Data Network**: Database traffic (internal only, no internet access)
- **Monitoring Network**: Metrics and observability

### Rootless Deployment

By default, Gitea runs in rootless mode (UID/GID 1000) for enhanced security.

## First-Time Setup

### 1. Generate Tokens

```bash
# Generate secure tokens
openssl rand -hex 32  # For secret_key
openssl rand -hex 64  # For internal_token
openssl rand -base64 32  # For oauth2_jwt_secret
```

### 2. Configure Actions Runner

After deployment:

1. Access Gitea Admin Panel
2. Navigate to Site Administration → Runners
3. Generate a registration token
4. Update terraform.tfvars with the token
5. Run `terraform apply` to update

### 3. Configure SSH Keys

```bash
# Generate SSH key for Git operations
ssh-keygen -t ed25519 -C "your-email@example.com"

# Add to Gitea
cat ~/.ssh/id_ed25519.pub
# Copy and add to Gitea user settings
```

### 4. Create First Repository

```bash
# Clone via SSH
git clone ssh://git@localhost:10001/username/repo.git

# Clone via HTTP
git clone http://localhost:10000/username/repo.git
```

## Upgrade Procedure

### 1. Backup Data

```bash
# Backup volumes
docker run --rm -v gitea_data:/data -v $(pwd):/backup alpine tar czf /backup/gitea_data_backup.tar.gz /data
docker run --rm -v postgres_gitea_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz /data
```

### 2. Update Module

```hcl
# Update image versions in terraform.tfvars
gitea_image = "gitea/gitea:1.22-rootless"  # New version
```

### 3. Apply Changes

```bash
# Plan changes
terraform plan

# Apply with minimal downtime
terraform apply

# Verify health
curl http://localhost:10000/api/healthz
```

## Monitoring

### Health Checks

```bash
# Check Gitea health
curl http://localhost:10000/api/healthz

# Check dashboard health
curl http://localhost:8000/health

# Check all containers
docker ps --filter "label=com.devsecops.stack=gitea"
```

### Metrics

Access Prometheus metrics:
```bash
# Get metrics token
METRICS_TOKEN=$(terraform output -raw metrics_token)

# Fetch metrics
curl -H "Authorization: Bearer $METRICS_TOKEN" http://localhost:10000/metrics
```

### Logs

```bash
# View Gitea logs
docker logs gitea

# View PostgreSQL logs
docker logs postgres-gitea

# View runner logs
docker logs gitea-runner
```

## Troubleshooting

### Container Issues

```bash
# Check container status
docker ps -a --filter "label=com.devsecops.stack=gitea"

# Inspect container
docker inspect gitea

# View logs
docker logs --tail 100 -f gitea
```

### Database Connection

```bash
# Test database connection
docker exec postgres-gitea psql -U gitea -d gitea -c "SELECT version();"

# Check database size
docker exec postgres-gitea psql -U gitea -d gitea -c "SELECT pg_database_size('gitea');"
```

### Network Issues

```bash
# List networks
docker network ls | grep gitea

# Inspect network
docker network inspect gitea_default
```

### Cleanup

```bash
# Destroy all resources
terraform destroy

# Clean up volumes (WARNING: Deletes all data!)
docker volume rm gitea_data gitea_config postgres_gitea_data
```

## Compliance

### CMMC Controls

The module implements the following CMMC Level 2 controls:

- **AC.L2-3.1.1**: Access Control
- **AU.L2-3.3.1**: Audit Logging
- **IA.L2-3.5.1**: Identification & Authentication
- **SC.L2-3.13.8**: Data in Transit Protection
- **SC.L2-3.13.11**: Cryptographic Protection
- **SI.L2-3.14.1**: System Monitoring
- **CM.L2-3.4.2**: Configuration Management

### Evidence Logging

Deployment evidence is automatically generated in:
```
./deployment_evidence_YYYY-MM-DD_HHmmss.json
```

## Support

For issues or questions:

1. Check container logs: `docker logs <container-name>`
2. Review evidence log: `cat deployment_evidence_*.json`
3. Verify network connectivity: `docker network inspect gitea_default`
4. Check resource usage: `docker stats`

## License

This module is provided as-is for DevSecOps platform deployment.