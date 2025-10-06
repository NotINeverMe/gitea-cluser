# Phase 1A Deployment Guide: Critical Security Foundation

## Overview

Phase 1A implements the critical security foundation for the Gitea DevSecOps platform, establishing SAST, container security, and infrastructure security scanning capabilities aligned with CMMC 2.0 Level 2 and NIST SP 800-171 Rev. 2 requirements.

**Estimated Deployment Time:** 4-6 hours
**Complexity Level:** Moderate
**Prerequisites Knowledge:** Basic Docker, Git, CI/CD concepts

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Deployment Steps](#deployment-steps)
4. [Post-Deployment Configuration](#post-deployment-configuration)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)
7. [Security Considerations](#security-considerations)
8. [Compliance Mapping](#compliance-mapping)

## Prerequisites

### System Requirements

- **OS:** Ubuntu 20.04+ / Debian 11+ / RHEL 8+ / macOS 12+
- **CPU:** Minimum 4 cores, recommended 8 cores
- **RAM:** Minimum 8GB, recommended 16GB
- **Storage:** Minimum 50GB free space
- **Network:** Stable internet connection for pulling images

### Software Requirements

```bash
# Required tools
docker >= 20.10
docker-compose >= 2.0
git >= 2.30
curl >= 7.68
jq >= 1.6
openssl >= 1.1.1

# Optional but recommended
make >= 4.2
kubectl >= 1.25 (if using Kubernetes)
gcloud SDK (for GCP integration)
```

### Access Requirements

- Admin access to Gitea instance
- Ability to create repository secrets
- Google Workspace account (for Google Chat webhooks)
- GCP project with appropriate IAM permissions (optional)

## Pre-Deployment Checklist

- [ ] System meets minimum requirements
- [ ] All required software installed
- [ ] Gitea instance running and accessible
- [ ] Backup of existing configurations (if any)
- [ ] Network ports available: 9000, 9001, 4954, 5432
- [ ] Docker daemon running with sufficient permissions
- [ ] At least 50GB free disk space
- [ ] Google Chat space created for alerts (optional)

## Deployment Steps

### Step 1: Clone Repository and Prepare Environment

```bash
# Clone the repository
cd /home/notme/Desktop
git clone <your-gitea-repo-url> gitea
cd gitea

# Make scripts executable
chmod +x scripts/*.sh

# Create required directories
mkdir -p evidence/phase1a logs data config
```

### Step 2: Run Automated Setup

```bash
# Execute the main setup script
./scripts/setup-phase1a.sh

# The script will:
# 1. Check prerequisites
# 2. Create directory structure
# 3. Generate secure passwords
# 4. Configure services
# 5. Start Docker containers
# 6. Initialize SonarQube
# 7. Run validation tests
```

**Expected Output:**
```
===========================================
Phase 1A: Critical Security Foundation Setup
CMMC 2.0 & NIST SP 800-171 Rev. 2 Compliance
===========================================

[2024-01-15 10:00:00] Checking prerequisites...
✓ All prerequisites met
[2024-01-15 10:00:05] Creating directory structure...
✓ Created: /home/notme/Desktop/gitea/evidence/phase1a
...
✓ Phase 1A deployment completed successfully!
```

### Step 3: Configure Google Chat Notifications (Optional)

```bash
# Run the Google Chat configuration script
./scripts/configure-gchat-webhooks.sh

# Select option 6 for full setup
# Follow the prompts to:
# 1. Create webhook in Google Chat
# 2. Enter webhook URL
# 3. Test connection
# 4. Create alert templates
```

### Step 4: Configure Gitea Secrets

Access your Gitea repository settings and add the following secrets:

| Secret Name | Description | Where to Find |
|------------|-------------|---------------|
| `SONAR_TOKEN` | SonarQube authentication token | Generated in .env file |
| `SONAR_HOST_URL` | SonarQube server URL | `http://localhost:9000` or your domain |
| `SEMGREP_APP_TOKEN` | Semgrep platform token | https://semgrep.dev/manage/settings |
| `INFRACOST_API_KEY` | Infracost API key | https://www.infracost.io/docs |
| `GCP_PROJECT_ID` | Your GCP project ID | GCP Console |
| `GCHAT_WEBHOOK_URL` | Google Chat webhook | From Step 3 |

### Step 5: Deploy Workflows to Repository

```bash
# Copy workflows to your repository
cp -r .gitea/workflows /path/to/your/repo/.gitea/

# Commit and push
cd /path/to/your/repo
git add .gitea/workflows
git commit -m "Add Phase 1A security scanning workflows

- SonarQube SAST analysis
- Semgrep advanced security scanning
- Container vulnerability scanning (Trivy/Grype)
- Terraform security analysis
- CMMC 2.0 & NIST 800-171 compliance checks

Co-Authored-By: DevSecOps Team <security@company.com>"
git push
```

## Post-Deployment Configuration

### Configure SonarQube

1. Access SonarQube at http://localhost:9000
2. Login with admin credentials (check .env file)
3. Configure the following:

```bash
# Quality Gates
- Navigate to Quality Gates
- Create "CMMC-NIST-Security" gate
- Set conditions:
  * Security Rating is worse than A
  * Reliability Rating is worse than A
  * Security Hotspots > 0
  * Coverage < 80%

# Security Rules
- Navigate to Rules
- Activate security rule packs:
  * OWASP Top 10
  * CWE Top 25
  * SANS Top 25

# Projects
- Create project for your repository
- Generate project token
- Update SONAR_TOKEN in Gitea secrets
```

### Configure Terraform Policies

```bash
# Install Terrascan policies
cd terraform/policies
terrascan init

# Test custom policies
opa test cmmc/cmmc-level2-gcp.rego
opa test nist/nist-800-171-gcp.rego

# Create policy bundle
opa build -b cmmc/ -b nist/ -o policies.bundle
```

### Set Up Evidence Collection

```bash
# Create evidence collection job
cat > .gitea/workflows/evidence-collection.yml << 'EOF'
name: Evidence Collection
on:
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight
  workflow_dispatch:

jobs:
  collect-evidence:
    runs-on: ubuntu-latest
    steps:
      - name: Collect scan evidence
        run: |
          # Collect all scan results
          find . -name "*-evidence.log" -exec sha256sum {} \; > daily-evidence.sha256

          # Archive to GCS
          gsutil cp daily-evidence.sha256 gs://evidence-bucket/$(date +%Y%m%d)/
EOF
```

## Verification

### Service Health Checks

```bash
# Check all services are running
docker-compose ps

# Expected output:
NAME                 STATUS    PORTS
sonarqube           healthy    0.0.0.0:9000->9000/tcp
sonarqube-postgres  healthy    5432/tcp
trivy-server        healthy    0.0.0.0:4954->4954/tcp
evidence-logger     running

# Test SonarQube API
curl -s http://localhost:9000/api/system/status | jq .status
# Expected: "UP"

# Test Trivy
docker exec trivy-server trivy version
# Expected: Version information

# Check logs for errors
docker-compose logs --tail=50 | grep -i error
```

### Workflow Execution Test

```bash
# Trigger a test scan
cd /path/to/your/repo

# Create a test file with intentional issue
cat > test-security.py << 'EOF'
import os
password = "hardcoded123"  # Security issue for testing
os.system("rm -rf /")  # Dangerous command
EOF

# Commit and push
git add test-security.py
git commit -m "Test security scanning"
git push

# Monitor workflow execution in Gitea Actions
# Expect to see security findings reported
```

### Validate Compliance Evidence

```bash
# Check evidence generation
ls -la evidence/phase1a/

# Verify evidence hashes
cd evidence/phase1a
sha256sum -c *.sha256

# Review validation report
cat validation-report.txt
```

## Troubleshooting

### Common Issues and Solutions

#### Issue: SonarQube fails to start

```bash
# Check logs
docker-compose logs sonarqube

# Common fixes:
# 1. Increase vm.max_map_count
sudo sysctl -w vm.max_map_count=262144

# 2. Check disk space
df -h

# 3. Reset and restart
docker-compose down -v
docker-compose up -d
```

#### Issue: Trivy database update fails

```bash
# Manual database update
docker exec trivy-server trivy image --download-db-only

# Use offline database
wget https://github.com/aquasecurity/trivy-db/releases/latest/download/db.tar.gz
tar -xzf db.tar.gz -C /tmp/trivy-cache/db
```

#### Issue: Workflows not triggering

```bash
# Check Gitea Actions runner
docker logs gitea-runner

# Verify webhook configuration
curl -X GET http://localhost:3000/api/v1/repos/{owner}/{repo}/hooks

# Check workflow syntax
act -l -W .gitea/workflows/
```

#### Issue: Google Chat notifications not working

```bash
# Test webhook manually
./scripts/send-gchat-alert.sh MEDIUM "Test" "Testing webhook"

# Check webhook URL format
echo $GCHAT_WEBHOOK_URL | grep -E "^https://chat.googleapis.com"

# Verify network connectivity
curl -I https://chat.googleapis.com
```

### Log Locations

- SonarQube: `docker-compose logs sonarqube`
- PostgreSQL: `docker-compose logs sonarqube-postgres`
- Trivy: `docker-compose logs trivy-server`
- Setup script: `evidence/phase1a/setup-*.log`
- Workflows: Gitea Actions UI

## Security Considerations

### Password Management

1. **Change default passwords immediately**
   ```bash
   # Update .env file with strong passwords
   openssl rand -base64 32  # Generate new password
   ```

2. **Rotate tokens regularly**
   - SonarQube tokens: Monthly
   - API keys: Quarterly
   - Webhook URLs: Annually

### Network Security

```bash
# Restrict access to management ports
# Add firewall rules
sudo ufw allow from 10.0.0.0/8 to any port 9000  # SonarQube
sudo ufw allow from 10.0.0.0/8 to any port 4954  # Trivy

# Use reverse proxy for external access
# Example nginx configuration in config/nginx/sonarqube.conf
```

### Data Protection

1. **Enable encryption at rest**
   ```bash
   # For Docker volumes
   docker volume create --driver local \
     --opt type=none \
     --opt device=/encrypted/path \
     --opt o=bind encrypted_volume
   ```

2. **Backup critical data**
   ```bash
   # Daily backup script
   ./scripts/backup-phase1a.sh
   ```

3. **Audit log retention**
   - Minimum 90 days for CMMC compliance
   - 7 years for evidence artifacts

## Compliance Mapping

### CMMC 2.0 Level 2 Controls Implemented

| Control | Description | Implementation |
|---------|-------------|----------------|
| CA.L2-3.12.4 | Security flaw remediation | SonarQube + Semgrep scanning |
| RA.L2-3.11.2 | Vulnerability scanning | Trivy + Grype container scanning |
| SI.L2-3.14.2 | Malicious code protection | Multi-layer scanning approach |
| CM.L2-3.4.1 | Baseline configurations | Terraform security policies |
| AU.L2-3.3.1 | Audit record generation | Evidence logging with SHA-256 |

### NIST SP 800-171 Rev. 2 Controls Implemented

| Control | Requirement | Implementation |
|---------|------------|----------------|
| 3.11.2 | Scan for vulnerabilities | Automated scanning workflows |
| 3.14.1 | Identify system flaws | SAST/DAST integration |
| 3.14.2 | Report system flaws | Google Chat notifications |
| 3.14.3 | Monitor security alerts | Real-time alert routing |
| 3.4.1 | Establish baselines | Policy-as-code enforcement |

## Next Steps

After successful deployment of Phase 1A:

1. **Phase 1B (Week 2)**: DAST and Supply Chain Security
2. **Phase 2 (Weeks 3-4)**: Identity Management and Zero Trust
3. **Phase 3 (Weeks 5-6)**: Monitoring and Incident Response
4. **Phase 4 (Weeks 7-8)**: Compliance Automation
5. **Phase 5 (Weeks 9-10)**: Advanced Threat Detection

## Support and Resources

- **Documentation**: `/docs` directory
- **Evidence**: `/evidence/phase1a` directory
- **Logs**: `docker-compose logs` and `/logs` directory
- **Scripts**: `/scripts` directory
- **Policies**: `/terraform/policies` directory

## Maintenance Schedule

- **Daily**: Review security alerts, check service health
- **Weekly**: Update vulnerability databases, review findings
- **Monthly**: Rotate tokens, update baselines
- **Quarterly**: Security audit, compliance review

---

*Document Version: 1.0.0*
*Last Updated: 2024-01-15*
*Classification: Internal Use*