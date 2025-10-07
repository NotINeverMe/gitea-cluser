# Gitea Stack Terraform Module - Deployment Guide

## Overview

This comprehensive Terraform module deploys a production-ready Gitea platform with:
- **Gitea Git Server** (v1.21) with rootless security
- **PostgreSQL 15** database with isolated network
- **Gitea Actions Runner** for CI/CD pipelines
- **Caddy** reverse proxy with automatic HTTPS
- **DevSecOps Dashboard** for monitoring and management
- **Security hardening** with CMMC Level 2 compliance controls
- **Evidence logging** for audit and compliance

## Module Structure

```
/home/notme/Desktop/gitea/terraform/gitea-stack/
├── main.tf                 # Main resources and locals
├── variables.tf            # Input variables (100+ configurable options)
├── outputs.tf              # Module outputs (20+ outputs)
├── versions.tf             # Provider versions and token generation
├── docker-networks.tf      # Three isolated Docker networks
├── docker-volumes.tf       # Persistent volumes with lifecycle protection
├── postgres.tf             # PostgreSQL container with health checks
├── gitea.tf                # Gitea server container
├── runner.tf               # Actions runner (conditional)
├── caddy.tf                # Caddy proxy (conditional)
├── dashboard.tf            # DevSecOps dashboard (conditional)
├── Makefile                # Automation for common operations
├── README.md               # Comprehensive documentation
├── terraform.tfvars.example # Example configuration
├── .gitignore              # Git ignore rules
└── DEPLOYMENT_GUIDE.md     # This file
```

## Quick Start Commands

### 1. Basic Deployment

```bash
# Navigate to module directory
cd /home/notme/Desktop/gitea/terraform/gitea-stack

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration (REQUIRED: set admin_password)
nano terraform.tfvars

# Initialize and deploy
make init
make apply

# View service URLs
make show-urls
```

### 2. Using Make Targets

```bash
# Format and validate code
make format
make validate

# Security scanning
make security-scan      # Scan Terraform code
make container-scan      # Scan Docker images

# Operations
make health             # Check service health
make logs               # View container logs
make backup             # Backup volumes
make evidence           # Generate compliance evidence

# Cleanup
make destroy            # Remove all resources
make clean              # Clean temp files
```

### 3. Direct Terraform Commands

```bash
# Initialize
terraform init

# Plan deployment
terraform plan -var-file=terraform.tfvars

# Apply configuration
terraform apply -var-file=terraform.tfvars

# View outputs
terraform output
terraform output -json > outputs.json

# Destroy resources
terraform destroy -var-file=terraform.tfvars
```

## Security Features

### Automatic Token Generation
The module automatically generates secure random tokens if not provided:

- **Secret Key**: 64 characters for session encryption
- **Internal Token**: 128 characters for service communication
- **OAuth2 JWT Secret**: 44 characters for JWT signing
- **Database Password**: 32 characters with special characters
- **Metrics Token**: 32 characters for Prometheus endpoint

### Password Policy
Admin password requirements (enforced by validation):
- Minimum 14 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one digit
- At least one special character

### Network Isolation
Three separate Docker networks:
- **Default** (172.20.0.0/16): General communication
- **Data** (172.21.0.0/16): Database traffic, internal only
- **Monitoring** (172.22.0.0/16): Metrics and observability

### Container Security
- Rootless Gitea deployment (UID/GID 1000)
- Resource limits on all containers
- Health checks with automatic restart
- Log rotation configured
- Volume lifecycle protection

## Variable Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `admin_password` | Admin password (14+ chars, complex) | `SuperSecure123!@#` |

### Key Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `stack_name` | `gitea` | Stack identifier |
| `gitea_domain` | `localhost` | Domain name |
| `gitea_http_port` | `10000` | HTTP port |
| `gitea_ssh_port` | `10001` | SSH port |
| `postgres_port` | `10002` | Database port |
| `enable_runner` | `true` | Enable CI/CD runner |
| `enable_caddy` | `false` | Enable HTTPS proxy |
| `enable_dashboard` | `true` | Enable dashboard |
| `gitea_cpu_limit` | `4` | CPU cores for Gitea |
| `gitea_memory_limit` | `4096` | Memory in MB |

## Evidence and Compliance

### CMMC Level 2 Controls
The module implements these controls:
- **AC.L2-3.1.1**: Access Control
- **AU.L2-3.3.1**: Audit Logging
- **IA.L2-3.5.1**: Identification & Authentication
- **SC.L2-3.13.8**: Data in Transit Protection
- **SC.L2-3.13.11**: Cryptographic Protection
- **SI.L2-3.14.1**: System Monitoring
- **CM.L2-3.4.2**: Configuration Management

### Evidence Generation
Deployment evidence is automatically created:
- Location: `deployment_evidence_YYYY-MM-DD_HHmmss.json`
- Contents: Timestamps, configuration, security settings, resource limits
- Format: JSON for automated processing

### Generate Compliance Report
```bash
make evidence
# Creates evidence/<timestamp>/ with:
# - report.md: Human-readable summary
# - state.json: Full Terraform state
# - containers.json: Container status
# - security.json: Security configuration
```

## Production Deployment

### 1. Prerequisites
```bash
# Install required tools
make install-tools

# Generate SSH key for Git
make ssh-setup
```

### 2. Production Configuration
```hcl
# terraform.tfvars for production
admin_username = "admin"
admin_password = "${env.GITEA_ADMIN_PASSWORD}"  # From environment/vault
admin_email    = "admin@company.com"

gitea_domain = "git.company.com"
gitea_root_url = "https://git.company.com/"

# Enable production features
enable_runner    = true
enable_caddy     = true   # HTTPS enabled
enable_dashboard = true

# Security hardening
gitea_disable_registration = true
gitea_cookie_secure        = true
gitea_rootless             = true

# Resource limits for production
gitea_cpu_limit    = 8
gitea_memory_limit = 8192
postgres_cpu_limit = 4
postgres_memory_limit = 4096
```

### 3. Deploy with CI/CD
```yaml
# .github/workflows/deploy.yml example
name: Deploy Gitea Stack
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Deploy
        env:
          GITEA_ADMIN_PASSWORD: ${{ secrets.GITEA_ADMIN_PASSWORD }}
        run: |
          cd terraform/gitea-stack
          make ci-validate
          make ci-deploy
```

### 4. Backup Strategy
```bash
# Automated daily backups
crontab -e
# Add: 0 2 * * * cd /path/to/module && make backup

# Manual backup before upgrades
make backup

# Restore from backup
make restore
# Enter timestamp when prompted
```

## Monitoring and Maintenance

### Health Monitoring
```bash
# Check all services
make health

# Direct health checks
curl http://localhost:10000/api/healthz
curl http://localhost:8000/health

# Container status
docker ps --filter "label=com.devsecops.stack=gitea"
```

### Metrics Collection
```bash
# Get metrics token
METRICS_TOKEN=$(terraform output -raw metrics_token)

# Fetch Prometheus metrics
curl -H "Authorization: Bearer $METRICS_TOKEN" \
     http://localhost:10000/metrics
```

### Log Analysis
```bash
# View logs interactively
make logs

# Direct log access
docker logs gitea --tail 100 -f
docker logs postgres-gitea --tail 50
docker logs gitea-runner --tail 100 -f
```

## Troubleshooting

### Common Issues

1. **Port Conflicts**
   ```bash
   # Check port usage
   netstat -tulpn | grep -E '10000|10001|10002'

   # Change ports in terraform.tfvars
   gitea_http_port = 11000
   gitea_ssh_port  = 11001
   ```

2. **Database Connection Issues**
   ```bash
   # Test database
   docker exec postgres-gitea psql -U gitea -d gitea -c "SELECT 1;"

   # Check network
   docker network inspect gitea_data
   ```

3. **Runner Registration**
   ```bash
   # Get runner token from Gitea admin panel
   # Update terraform.tfvars
   gitea_runner_token = "TOKEN_FROM_GITEA"

   # Reapply
   terraform apply -target=docker_container.gitea_runner
   ```

## Module Outputs

The module provides 20+ outputs including:

- **URLs**: `gitea_url`, `dashboard_url`, `gitea_ssh_url`
- **Credentials**: `admin_username`, `admin_credentials_file`
- **Container IDs**: `container_ids` (all services)
- **Networks**: `network_ids`, `network_names`
- **Volumes**: `volume_names`
- **API Endpoints**: `api_endpoints`, `metrics_endpoint`
- **Security Config**: `security_config`
- **Evidence**: `evidence_log_file`

## Files Created

### Terraform Module Files (17 files)
- `/home/notme/Desktop/gitea/terraform/gitea-stack/main.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/variables.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/outputs.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/versions.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/docker-networks.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/docker-volumes.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/postgres.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/gitea.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/runner.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/caddy.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/dashboard.tf`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/README.md`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/Makefile`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/terraform.tfvars.example`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/.gitignore`
- `/home/notme/Desktop/gitea/terraform/gitea-stack/DEPLOYMENT_GUIDE.md`

### Example Usage Files (2 files)
- `/home/notme/Desktop/gitea/terraform/example/main.tf`
- `/home/notme/Desktop/gitea/terraform/example/terraform.tfvars.example`

### Generated at Runtime
- `.gitea_admin.json` - Admin credentials (sensitive)
- `.postgres_connection.json` - Database connection (sensitive)
- `.dashboard_config.json` - Dashboard configuration
- `deployment_evidence_*.json` - Compliance evidence
- `Caddyfile` - Generated if not provided
- `runner-config.yaml` - Generated if not provided

## Best Practices

1. **Security**
   - Never commit terraform.tfvars with passwords
   - Use environment variables or vault for secrets
   - Enable HTTPS in production with Caddy
   - Regularly update container images

2. **Backup**
   - Automate daily backups with cron
   - Test restore procedures regularly
   - Keep 30 days of backups minimum

3. **Monitoring**
   - Set up alerts for health endpoints
   - Monitor resource usage
   - Review logs for security events

4. **Updates**
   - Test updates in staging first
   - Create backups before updates
   - Use blue-green deployments for zero downtime

## Support

For issues or questions:
1. Check logs: `make logs`
2. Verify health: `make health`
3. Review evidence: `cat deployment_evidence_*.json`
4. Check container status: `docker ps -a`

---

Module Version: 1.0.0
Created: 2025-10-06
Platform: DevSecOps Engineering