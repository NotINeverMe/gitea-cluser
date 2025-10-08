# GCP Gitea Deployment Guide

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Pre-Deployment Checklist](#pre-deployment-checklist)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [DNS and SSL Configuration](#dns-and-ssl-configuration)
6. [Post-Deployment Verification](#post-deployment-verification)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Security Hardening](#security-hardening)
9. [Cost Optimization](#cost-optimization)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                │
└────────────────────┬────────────────────────────────────────────┘
                     │
              ┌──────▼──────┐
              │ Cloud Armor │ (WAF Protection)
              └──────┬──────┘
                     │
         ┌───────────▼───────────┐
         │   External IP         │
         │   Load Balancer       │
         └───────────┬───────────┘
                     │
    ┌────────────────▼────────────────┐
    │         VPC Network              │
    │   ┌─────────────────────────┐   │
    │   │   Gitea Subnet          │   │
    │   │   10.0.1.0/24           │   │
    │   └─────────┬───────────────┘   │
    │             │                    │
    │   ┌─────────▼───────────┐       │
    │   │   Compute Instance   │       │
    │   │   (Shielded VM)      │       │
    │   │                      │       │
    │   │  ┌──────────────┐   │       │
    │   │  │ Docker       │   │       │
    │   │  │  ├─ Gitea    │   │       │
    │   │  │  ├─ Postgres │   │       │
    │   │  │  └─ Redis    │   │       │
    │   │  └──────────────┘   │       │
    │   │                      │       │
    │   │  Disks:              │       │
    │   │  ├─ Boot (200GB SSD) │       │
    │   │  └─ Data (500GB SSD) │       │
    │   └──────────────────────┘       │
    │                                  │
    └──────────────────────────────────┘
                     │
         ┌───────────┴──────────────┐
         │    Cloud Storage         │
         │  ┌──────────────────┐   │
         │  │ Evidence Bucket  │   │
         │  ├──────────────────┤   │
         │  │ Backup Bucket    │   │
         │  ├──────────────────┤   │
         │  │ Logs Bucket      │   │
         │  └──────────────────┘   │
         └──────────────────────────┘
                     │
         ┌───────────▼──────────┐
         │  Security Services   │
         │  ├─ Cloud KMS        │
         │  ├─ Secret Manager   │
         │  ├─ IAP             │
         │  └─ Cloud Monitoring │
         └──────────────────────┘
```

### Key Components

| Component | Purpose | CMMC Control |
|-----------|---------|--------------|
| Shielded VM | Secure boot, vTPM, integrity monitoring | SC.L2-3.13.15 |
| Cloud KMS | Encryption key management | SC.L2-3.13.11 |
| Secret Manager | Credential storage | IA.L2-3.5.1 |
| Cloud Armor | WAF protection | SC.L2-3.13.5 |
| IAP | Secure SSH access | AC.L2-3.1.1 |
| GCS Buckets | Evidence, backups, logs | AU.L2-3.3.8 |

## Prerequisites

### Required Tools

```bash
# Check installed tools
command -v gcloud >/dev/null 2>&1 && echo "✓ gcloud installed" || echo "✗ gcloud missing"
command -v terraform >/dev/null 2>&1 && echo "✓ terraform installed" || echo "✗ terraform missing"
command -v jq >/dev/null 2>&1 && echo "✓ jq installed" || echo "✗ jq missing"
command -v curl >/dev/null 2>&1 && echo "✓ curl installed" || echo "✗ curl missing"
```

### Install Missing Tools

```bash
# Install gcloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Install jq
sudo apt-get install jq

# Verify installations
gcloud version
terraform version
jq --version
```

### GCP Project Setup

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Create project (if needed)
gcloud projects create $PROJECT_ID --name="Gitea Infrastructure"

# Set as current project
gcloud config set project $PROJECT_ID

# Link billing account
gcloud beta billing accounts list
gcloud beta billing projects link $PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
```

### Required IAM Permissions

The deploying user needs the following roles:
- `roles/compute.admin` - Manage compute resources
- `roles/storage.admin` - Manage storage buckets
- `roles/iam.serviceAccountAdmin` - Create service accounts
- `roles/secretmanager.admin` - Manage secrets
- `roles/monitoring.editor` - Configure monitoring

Grant permissions:
```bash
# Replace USER_EMAIL with your email
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:USER_EMAIL" \
    --role="roles/owner"
```

## Pre-Deployment Checklist

### Configuration Requirements

- [ ] **Project ID** - Valid GCP project with billing enabled
- [ ] **Domain Name** - Registered domain for Gitea access
- [ ] **Admin Email** - Valid email for notifications
- [ ] **SSH Keys** - SSH key pair for Git operations (optional)
- [ ] **IP Allowlist** - List of IPs for Git SSH access (optional)

### Cost Estimates

| Environment | Instance Type | Storage | Estimated Monthly Cost |
|-------------|--------------|---------|------------------------|
| Dev | e2-standard-4 | 300GB SSD | ~$150/month |
| Staging | e2-standard-4 | 400GB SSD | ~$175/month |
| Production | e2-standard-8 | 700GB SSD | ~$350/month |

*Note: Costs vary by region and include compute, storage, and network egress.*

### Network Planning

- **VPC CIDR**: Default `10.0.1.0/24` (256 IPs)
- **External IP**: Static IP will be allocated
- **Firewall Rules**:
  - HTTPS (443): Open to all (`0.0.0.0/0`)
  - SSH (22): IAP only (`35.235.240.0/20`)
  - Git SSH (10022): Configurable allowlist

## Step-by-Step Deployment

### 1. Clone Repository

```bash
git clone https://github.com/your-org/gitea-infrastructure.git
cd gitea-infrastructure
```

### 2. Configure Environment

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export DOMAIN="git.example.com"
export ADMIN_EMAIL="admin@example.com"
export ENVIRONMENT="prod"  # or dev, staging
```

### 3. Run Deployment Script

```bash
# Make script executable
chmod +x scripts/gcp-deploy.sh

# Run deployment
./scripts/gcp-deploy.sh \
  -p $PROJECT_ID \
  -d $DOMAIN \
  -a $ADMIN_EMAIL \
  -e $ENVIRONMENT
```

### 4. Monitor Deployment

The deployment will:
1. Enable required APIs
2. Initialize Terraform
3. Create infrastructure
4. Deploy Gitea containers
5. Configure security settings
6. Generate compliance evidence

Expected duration: 15-20 minutes

### 5. Deployment Output

Upon successful deployment, you'll receive:
- External IP address
- SSH access commands
- Storage bucket names
- Monitoring dashboard URL
- Evidence file location

## DNS and SSL Configuration

### Configure DNS

1. **Get External IP**:
```bash
EXTERNAL_IP=$(cd terraform/gcp-gitea && terraform output -raw instance_external_ip)
echo "External IP: $EXTERNAL_IP"
```

2. **Create A Record**:
   - Log into your DNS provider
   - Create A record: `git.example.com` → `EXTERNAL_IP`
   - TTL: 300 seconds (for testing), 3600 seconds (production)

3. **Verify DNS**:
```bash
# Check DNS propagation
dig +short git.example.com
nslookup git.example.com
```

### SSL Certificate Setup

#### Option 1: Let's Encrypt (Recommended)

```bash
# SSH to instance
gcloud compute ssh gitea-$ENVIRONMENT-server \
  --zone=us-central1-a \
  --tunnel-through-iap

# Install certbot
sudo apt-get update
sudo apt-get install certbot

# Generate certificate
sudo certbot certonly --standalone \
  -d git.example.com \
  --email admin@example.com \
  --agree-tos \
  --non-interactive

# Configure Gitea to use certificate
sudo vi /opt/gitea/config/app.ini
# Add under [server]:
# PROTOCOL = https
# CERT_FILE = /etc/letsencrypt/live/git.example.com/fullchain.pem
# KEY_FILE = /etc/letsencrypt/live/git.example.com/privkey.pem

# Restart Gitea
cd /opt/gitea && sudo docker-compose restart gitea
```

#### Option 2: Cloud Load Balancer with Managed Certificate

```bash
# Create managed certificate
gcloud compute ssl-certificates create gitea-cert \
  --domains=git.example.com \
  --global

# Create health check
gcloud compute health-checks create https gitea-health \
  --port=443 \
  --request-path=/api/v1/version

# Configure load balancer (see terraform/modules/load-balancer)
```

### Firewall Configuration

```bash
# Allow HTTPS from anywhere
gcloud compute firewall-rules create allow-gitea-https \
  --allow tcp:443 \
  --source-ranges 0.0.0.0/0 \
  --target-tags gitea-server

# Allow Git SSH from specific IPs (optional)
gcloud compute firewall-rules create allow-gitea-git-ssh \
  --allow tcp:10022 \
  --source-ranges YOUR_IP_RANGE \
  --target-tags gitea-server
```

## Post-Deployment Verification

### 1. Instance Health Check

```bash
# Check instance status
gcloud compute instances describe gitea-$ENVIRONMENT-server \
  --zone=us-central1-a \
  --format="value(status)"

# View startup logs
gcloud compute instances get-serial-port-output \
  gitea-$ENVIRONMENT-server \
  --zone=us-central1-a | tail -50
```

### 2. Service Verification

```bash
# Check Gitea API
curl -k https://$EXTERNAL_IP/api/v1/version

# Check web interface
curl -I https://$DOMAIN

# SSH to instance for detailed checks
gcloud compute ssh gitea-$ENVIRONMENT-server \
  --zone=us-central1-a \
  --tunnel-through-iap

# On instance: Check Docker containers
sudo docker ps
sudo docker-compose logs --tail=50
```

### 3. Storage Verification

```bash
# List storage buckets
gsutil ls -p $PROJECT_ID

# Check evidence bucket
gsutil ls gs://gitea-$ENVIRONMENT-evidence-$PROJECT_ID/

# Check backup bucket
gsutil ls gs://gitea-$ENVIRONMENT-backup-$PROJECT_ID/
```

### 4. Initial Gitea Setup

1. Navigate to `https://git.example.com`
2. Complete initial configuration:
   - Database: Already configured (PostgreSQL)
   - Site Title: Your Organization
   - Repository Root Path: /data/git/repositories
   - LFS Root Path: /data/git/lfs
   - Admin Account: Use configured credentials

### 5. Test Git Operations

```bash
# Configure Git
git config --global user.name "Your Name"
git config --global user.email "your@email.com"

# Create test repository
curl -X POST "https://git.example.com/api/v1/user/repos" \
  -H "Authorization: token YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"test-repo","private":false}'

# Clone and test
git clone https://git.example.com/username/test-repo.git
cd test-repo
echo "# Test" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Instance Not Accessible

```bash
# Check instance status
gcloud compute instances describe gitea-$ENVIRONMENT-server \
  --zone=us-central1-a

# Check firewall rules
gcloud compute firewall-rules list --filter="targetTags:gitea-server"

# Check external IP
gcloud compute addresses list

# View logs
gcloud logging read "resource.type=gce_instance" --limit=50
```

#### Docker Containers Not Running

```bash
# SSH to instance
gcloud compute ssh gitea-$ENVIRONMENT-server \
  --zone=us-central1-a \
  --tunnel-through-iap

# Check Docker status
sudo systemctl status docker
sudo docker ps -a

# Restart containers
cd /opt/gitea
sudo docker-compose down
sudo docker-compose up -d

# Check logs
sudo docker-compose logs --tail=100
```

#### Database Connection Issues

```bash
# Check PostgreSQL
sudo docker exec -it gitea-postgres psql -U gitea -c "SELECT 1;"

# Check connection from Gitea
sudo docker exec -it gitea-gitea sh -c "nc -zv postgres 5432"

# Review database logs
sudo docker logs gitea-postgres --tail=50
```

#### SSL Certificate Issues

```bash
# Check certificate
openssl s_client -connect git.example.com:443 -servername git.example.com

# Renew Let's Encrypt certificate
sudo certbot renew --dry-run
sudo certbot renew

# Check certificate expiry
echo | openssl s_client -connect git.example.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### Performance Issues

```bash
# Check resource usage
gcloud compute instances get-serial-port-output \
  gitea-$ENVIRONMENT-server --zone=us-central1-a | grep -E "(CPU|Memory)"

# Monitor metrics
gcloud monitoring metrics-descriptors list --filter="metric.type:compute.googleapis.com"

# Check disk I/O
sudo iostat -x 5 3

# Docker stats
sudo docker stats --no-stream
```

## Security Hardening

### 1. Network Security

```bash
# Restrict SSH access to specific IPs
gcloud compute firewall-rules update allow-ssh \
  --source-ranges="YOUR_OFFICE_IP/32"

# Enable Cloud Armor DDoS protection
gcloud compute security-policies create gitea-waf \
  --description="Gitea WAF Policy"

gcloud compute security-policies rules create 1000 \
  --security-policy=gitea-waf \
  --action=deny-403 \
  --expression="origin.region_code == 'CN'"
```

### 2. Access Control

```bash
# Enable 2FA requirement in Gitea
# Navigate to Admin Panel → Configuration → Security
# Set: REQUIRE_TWO_FACTOR = true

# Configure session timeout
sudo vi /opt/gitea/config/app.ini
# Add:
# [session]
# SESSION_LIFE_TIME = 86400
# COOKIE_SECURE = true
# COOKIE_HTTPONLY = true
```

### 3. Encryption

```bash
# Verify disk encryption
gcloud compute disks describe gitea-$ENVIRONMENT-server \
  --zone=us-central1-a \
  --format="value(diskEncryptionKey)"

# Enable application-level encryption
# In app.ini:
# [security]
# SECRET_KEY = <generate-strong-key>
# INTERNAL_TOKEN = <generate-strong-token>
```

### 4. Audit Logging

```bash
# Enable audit logs
gcloud logging sinks create gitea-audit-sink \
  storage.googleapis.com/gitea-$ENVIRONMENT-logs-$PROJECT_ID \
  --log-filter='resource.type="gce_instance"'

# Configure Gitea audit logging
# In app.ini:
# [log]
# LEVEL = Info
# MODE = file
# ROOT_PATH = /data/gitea/log
```

### 5. Regular Security Updates

```bash
# Create update script
cat > /opt/gitea/update.sh << 'EOF'
#!/bin/bash
# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Update Docker images
cd /opt/gitea
sudo docker-compose pull
sudo docker-compose up -d

# Update Gitea
sudo docker exec gitea-gitea gitea manager flush-queues
EOF

chmod +x /opt/gitea/update.sh
```

## Cost Optimization

### 1. Right-Sizing Resources

```bash
# Monitor actual usage
gcloud monitoring dashboards create \
  --config-from-file=monitoring/dashboard.json

# Analyze recommendations
gcloud recommender recommendations list \
  --project=$PROJECT_ID \
  --location=us-central1-a \
  --recommender=google.compute.instance.MachineTypeRecommender
```

### 2. Committed Use Discounts

```bash
# Purchase 1-year commitment for production
gcloud compute commitments create gitea-commitment \
  --region=us-central1 \
  --resources=vcpu=8,memory=32GB \
  --plan=TWELVE_MONTH
```

### 3. Storage Optimization

```bash
# Set lifecycle rules for old backups
gsutil lifecycle set lifecycle.json gs://gitea-$ENVIRONMENT-backup-$PROJECT_ID/

# lifecycle.json:
{
  "lifecycle": {
    "rule": [{
      "action": {"type": "Delete"},
      "condition": {"age": 30}
    }]
  }
}
```

### 4. Network Egress Optimization

- Use Cloud CDN for static assets
- Configure caching headers
- Minimize cross-region transfers
- Use private Google Access for GCS

### 5. Monitoring Costs

```bash
# Set up budget alerts
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="Gitea Infrastructure" \
  --budget-amount=500 \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=90 \
  --threshold-rule=percent=100
```

## Maintenance Windows

### Recommended Schedule

| Task | Frequency | Window | Duration |
|------|-----------|--------|----------|
| Backups | Daily | 2:00 AM UTC | 30 min |
| Updates | Weekly | Sunday 3:00 AM UTC | 1 hour |
| Maintenance | Monthly | First Sunday | 2 hours |
| DR Testing | Quarterly | Scheduled | 4 hours |

### Maintenance Procedure

```bash
# 1. Announce maintenance
# 2. Create backup
./scripts/gcp-backup.sh -p $PROJECT_ID -e $ENVIRONMENT

# 3. Perform maintenance
gcloud compute instances stop gitea-$ENVIRONMENT-server --zone=us-central1-a
# ... perform tasks ...
gcloud compute instances start gitea-$ENVIRONMENT-server --zone=us-central1-a

# 4. Verify services
./scripts/health-check.sh

# 5. Notify completion
```

## Support and Resources

### Documentation
- [Gitea Documentation](https://docs.gitea.io/)
- [GCP Documentation](https://cloud.google.com/docs)
- [Terraform Documentation](https://www.terraform.io/docs)
- [CMMC Requirements](https://www.acq.osd.mil/cmmc/)

### Monitoring Dashboards
- GCP Console: `https://console.cloud.google.com/monitoring`
- Gitea Metrics: `https://git.example.com/metrics`
- Uptime Status: Configure external monitoring

### Emergency Contacts
- GCP Support: [Cloud Console Support](https://console.cloud.google.com/support)
- Security Issues: security@example.com
- Infrastructure Team: devops@example.com

---

*Last Updated: 2024*
*Version: 1.0*
*Compliance: CMMC Level 2 / NIST SP 800-171*