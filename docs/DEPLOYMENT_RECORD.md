# Gitea GCP Deployment Record

**CMMC 2.0 Level 2 Compliant Deployment - Production Environment**

---

## Deployment Overview

**Date**: 2025-10-07
**Environment**: Production
**GCP Organization**: dcg.cui-secure.us
**Deployed By**: nmartin@dcg.cui-secure.us
**Compliance**: CMMC 2.0 Level 2, NIST SP 800-171 Rev. 2

---

## 1. GCP Project Creation

### 1.1 Project Details

```
Project ID:       cui-gitea-prod
Project Name:     Gitea Production
Project Number:   1018248415137
Organization ID:  1024722247064
Organization:     dcg.cui-secure.us
Billing Account:  01B48D-9AF35D-EC356C (My Billing Account)
Billing Status:   ACTIVE
Lifecycle State:  ACTIVE
Region:           us-central1
Zone:             us-central1-a
```

### 1.2 Creation Commands

**Authenticated User**:
```bash
gcloud auth list
# ACTIVE: nmartin@dcg.cui-secure.us
```

**Organization Verification**:
```bash
gcloud organizations list
# DISPLAY_NAME: dcg.cui-secure.us
# ID: 1024722247064
# DIRECTORY_CUSTOMER_ID: C00hjh9b2
```

**Billing Account Verification**:
```bash
gcloud billing accounts list
# ACCOUNT_ID: 01B48D-9AF35D-EC356C
# NAME: My Billing Account
# OPEN: True
```

**Project Creation**:
```bash
gcloud projects create cui-gitea-prod \
  --organization=1024722247064 \
  --name="Gitea Production" \
  --set-as-default
```

**Output**:
```
Create in progress for [https://cloudresourcemanager.googleapis.com/v1/projects/cui-gitea-prod].
Waiting for [operations/create_project.global.5264266711896403735] to finish...done.
Enabling service [cloudapis.googleapis.com] on project [cui-gitea-prod]...
Operation "operations/acat.p2-1018248415137-5c47c134-41c5-4135-9b30-e6aadc644763" finished successfully.
Updated property [core/project] to [cui-gitea-prod].
```

**Billing Link**:
```bash
gcloud billing projects link cui-gitea-prod \
  --billing-account=01B48D-9AF35D-EC356C
```

**Output**:
```
billingAccountName: billingAccounts/01B48D-9AF35D-EC356C
billingEnabled: true
name: projects/cui-gitea-prod/billingInfo
projectId: cui-gitea-prod
```

### 1.3 API Enablement

**Enabled APIs**:
```bash
gcloud services enable \
  compute.googleapis.com \
  storage.googleapis.com \
  cloudkms.googleapis.com \
  secretmanager.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  serviceusage.googleapis.com \
  --project=cui-gitea-prod
```

**Verification**:
```bash
gcloud services list --enabled --project=cui-gitea-prod
```

**Enabled Services** (9 core APIs):
1. `compute.googleapis.com` - Compute Engine (VMs, networking)
2. `storage.googleapis.com` - Cloud Storage (buckets, objects)
3. `cloudkms.googleapis.com` - Cloud KMS (encryption keys)
4. `secretmanager.googleapis.com` - Secret Manager (credentials)
5. `monitoring.googleapis.com` - Cloud Monitoring (metrics, alerts)
6. `logging.googleapis.com` - Cloud Logging (audit logs)
7. `cloudresourcemanager.googleapis.com` - Resource Manager (projects)
8. `iam.googleapis.com` - IAM (service accounts, permissions)
9. `serviceusage.googleapis.com` - Service Usage (API management)

**Additional Auto-enabled Services**:
- `bigquerystorage.googleapis.com` - BigQuery Storage API
- `storage-api.googleapis.com` - Storage API v1
- `storage-component.googleapis.com` - Storage Component

### 1.4 Project Configuration

**Set Default Project**:
```bash
gcloud config set project cui-gitea-prod
```

**Verify Configuration**:
```bash
gcloud config get-value project
# Output: cui-gitea-prod

gcloud projects describe cui-gitea-prod
```

**Output**:
```
PROJECT_ID      NAME              PROJECT_NUMBER  LIFECYCLE_STATE
cui-gitea-prod  Gitea Production  1018248415137   ACTIVE
```

---

## 2. Terraform Configuration Updates

### 2.1 Main Configuration (terraform.tfvars)

**Updated Parameters**:
```hcl
# GCP Project ID
project_id = "cui-gitea-prod"

# Region and Zone
region = "us-central1"
zone   = "us-central1-a"

# Domain Configuration
gitea_domain = "gitea.cui-secure.us"

# Admin Configuration
gitea_admin_username = "admin"
gitea_admin_email    = "nmartin@dcg.cui-secure.us"

# Secrets (stored in Secret Manager - not hardcoded)
gitea_admin_password = null  # Retrieved from Secret Manager
postgres_password    = null  # Retrieved from Secret Manager
```

**File Location**: `terraform/gcp-gitea/terraform.tfvars`

### 2.2 Bootstrap Configuration

**Created**: `terraform/gcp-gitea/bootstrap/terraform.tfvars`

```hcl
project_id          = "cui-gitea-prod"
region              = "us-central1"
environment         = "prod"
kms_location        = "us-central1"
bucket_location     = "US"
terraform_sa_email  = ""
```

**File Location**: `terraform/gcp-gitea/bootstrap/terraform.tfvars`

---

## 3. Deployment Architecture

### 3.1 Infrastructure Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    GCP Project: cui-gitea-prod                   │
│                  Organization: dcg.cui-secure.us                 │
└─────────────────────────────────────────────────────────────────┘
                                  │
                ┌─────────────────┴─────────────────┐
                │                                     │
         ┌──────▼──────┐                     ┌──────▼──────┐
         │  Bootstrap   │                     │  Main Stack  │
         │  (One-time)  │                     │  (Gitea)     │
         └──────┬───────┘                     └──────┬───────┘
                │                                     │
    ┌───────────┴───────────┐           ┌───────────┴────────────┐
    │                       │           │                         │
┌───▼───────────┐  ┌───────▼────────┐ ┌▼──────────┐  ┌──────────▼─┐
│ GCS Backend   │  │  KMS Keyring   │ │ Compute   │  │  Secret    │
│               │  │                │ │ Instance  │  │  Manager   │
│ • State       │  │ • 3 Keys       │ │           │  │            │
│ • Versioning  │  │ • 90d Rotate   │ │ • Ubuntu  │  │ • 10 Secrets│
│ • CMEK        │  │ • CMEK         │ │ • Shielded│  │ • Regional  │
└───────┬───────┘  └────────────────┘ │ • 8 vCPU  │  │ • CMEK      │
        │                              └───────────┘  └─────────────┘
        │                                     │
┌───────▼──────────┐                  ┌──────▼──────────────┐
│  Audit Bucket    │                  │  VPC Network        │
│                  │                  │                     │
│ • 7-year retain  │                  │ • Cloud NAT         │
│ • Immutable      │                  │ • Cloud Armor WAF   │
│ • Log sink       │                  │ • Firewall rules    │
└──────────────────┘                  │ • VPC Flow Logs     │
                                      └─────────────────────┘
```

### 3.2 Network Architecture

```
Internet
    │
    │ HTTPS (443)
    ▼
┌─────────────────────┐
│  Cloud Armor WAF    │  ◄─── OWASP Top 10 Protection
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Firewall Rules     │
│                     │
│ • HTTPS: 0.0.0.0/0  │
│ • SSH: IAP only     │
│ • Git SSH: Disabled │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────────────────────┐
│  VPC: cui-gitea-prod-vpc            │
│  Subnet: 10.0.1.0/24                │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  Gitea VM (10.0.1.x)          │ │
│  │                                │ │
│  │  • e2-standard-8               │ │
│  │  • Ubuntu 22.04 LTS            │ │
│  │  • Shielded VM                 │ │
│  │  • Docker Compose              │ │
│  │                                │ │
│  │  Services:                     │ │
│  │  ├─ Gitea                      │ │
│  │  ├─ PostgreSQL                 │ │
│  │  ├─ Caddy (HTTPS)              │ │
│  │  └─ Actions Runner             │ │
│  └────────────────────────────────┘ │
│                                      │
│  Cloud NAT ──► Internet (outbound)  │
│  Private Google Access: Enabled     │
└──────────────────────────────────────┘
```

### 3.3 Security Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Security Layers                          │
└──────────────────────────────────────────────────────────────┘

Layer 1: Network Security
├─ Cloud Armor WAF (DDoS, OWASP Top 10)
├─ Firewall Rules (Least privilege)
├─ VPC Flow Logs (Audit)
└─ Private Google Access (No public IPs for GCP services)

Layer 2: Compute Security
├─ Shielded VM (Secure Boot + vTPM + Integrity Monitoring)
├─ OS Login (Centralized SSH key management)
├─ Identity-Aware Proxy (Zero-trust SSH access)
└─ CIS Level 2 Hardening (Kernel, auditd, Fail2ban, AIDE)

Layer 3: Data Security
├─ Cloud KMS (CMEK encryption, 90-day rotation)
├─ Encrypted Disks (Boot + Data with separate keys)
├─ Encrypted Storage (GCS with CMEK)
└─ TLS 1.3 in Transit (Caddy with Let's Encrypt)

Layer 4: Secrets Management
├─ Secret Manager (All credentials)
├─ Zero secrets in code
├─ Runtime retrieval only
└─ IAM-based access control

Layer 5: Audit & Compliance
├─ Cloud Logging (7-year retention)
├─ State change audit (Immutable bucket)
├─ SHA256 checksums (Integrity verification)
└─ Evidence JSON (Assessor artifacts)
```

### 3.4 Service Accounts

**4 Service Accounts with Least Privilege**:

1. **cui-gitea-prod-terraform-deployer**
   - Purpose: CI/CD and operator deployments
   - Roles: compute.instanceAdmin.v1, storage.admin, secretmanager.secretAccessor, cloudkms.cryptoKeyEncrypterDecrypter

2. **cui-gitea-prod-gitea-vm**
   - Purpose: Gitea VM operations
   - Roles: logging.logWriter, monitoring.metricWriter, secretmanager.secretAccessor, storage.objectCreator, storage.objectViewer

3. **cui-gitea-prod-evidence-collector**
   - Purpose: Compliance automation
   - Roles: securitycenter.findingsViewer, cloudasset.viewer, logging.viewer, iam.securityReviewer, cloudkms.viewer, storage.objectCreator

4. **cui-gitea-prod-backup**
   - Purpose: Automated backups
   - Roles: compute.storageAdmin, storage.admin, logging.logWriter

---

## 4. Compliance Controls

### 4.1 CMMC 2.0 Level 2 Mappings

| Control | Requirement | Implementation |
|---------|-------------|----------------|
| **AC.L2-3.1.1** | Authorized Access Control | IAM service accounts, OS Login, IAP |
| **AU.L2-3.3.1** | Audit Logging | 7-year retention, state change logs |
| **AU.L2-3.3.8** | Audit Record Protection | Immutable audit bucket, CMEK encryption |
| **CM.L2-3.4.2** | Baseline Configuration | Versioned state/config, IaC |
| **CP.L2-3.11.1** | Information Backup | 30 state versions, automated backups |
| **IA.L2-3.5.1** | Identification & Authentication | Secret Manager, service account auth |
| **IA.L2-3.5.7** | Authenticator Feedback | Zero secrets in code |
| **SC.L2-3.13.8** | Transmission Confidentiality | TLS 1.3, HTTPS only |
| **SC.L2-3.13.11** | Cryptographic Protection | CMEK for all data at rest |
| **SC.L2-3.13.15** | Secure Boot | Shielded VM with Secure Boot + vTPM |
| **SI.L2-3.14.1** | System Monitoring | Cloud Monitoring, alerts, uptime checks |

### 4.2 NIST SP 800-171 Rev. 2 Mappings

| Section | Requirement | Implementation |
|---------|-------------|----------------|
| **§3.1.1** | Access Control | Least privilege IAM, MFA |
| **§3.3.1** | Audit Records | Comprehensive logging |
| **§3.3.8** | Audit Protection | 7-year immutable logs |
| **§3.4.2** | Configuration Baselines | Versioned infrastructure |
| **§3.5.1** | Authenticator Management | Secret Manager with rotation |
| **§3.5.7** | Password Obscuration | Secrets never in code |
| **§3.11.1** | Information Backups | Automated versioning |
| **§3.13.8** | Transmission Security | TLS encryption |
| **§3.13.11** | Cryptographic Key Management | KMS with 90-day rotation |
| **§3.14.1** | Flaw Remediation | State recovery, rollback |

---

## 5. Deployment Procedure

### 5.1 Pre-Deployment Checklist

- [x] GCP project created: `cui-gitea-prod`
- [x] Billing account linked and active
- [x] Required APIs enabled (9 APIs)
- [x] DNS configured: `gitea.cui-secure.us`
- [x] Terraform configurations updated
- [x] Bootstrap tfvars created
- [ ] Application Default Credentials set up
- [ ] State backend bootstrapped
- [ ] Secrets created in Secret Manager
- [ ] Backend.tf configured
- [ ] Infrastructure deployed
- [ ] Post-deployment verification

### 5.2 Deployment Steps

**Step 1: Application Default Credentials**
```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project cui-gitea-prod
```

**Step 2: Bootstrap State Backend**
```bash
cd terraform/gcp-gitea/bootstrap
terraform init
terraform plan
terraform apply
```

Expected Resources:
- GCS state bucket: `cui-gitea-prod-prod-tfstate-XXXXXXXXXX`
- GCS audit bucket: `cui-gitea-prod-prod-audit-XXXXXXXXXX`
- KMS keyring: `cui-gitea-prod-prod-gitea-keyring`
- KMS keys: tfstate-encryption-key, storage-encryption-key, secret-encryption-key
- Log sink: tfstate-audit-sink

**Step 3: Create Secrets**
```bash
cd ../../../scripts
./create-secrets.sh -p cui-gitea-prod -r us-central1
```

Expected Secrets (10):
1. gitea-admin-password
2. postgres-password
3. gitea-secret-key
4. gitea-internal-token
5. gitea-oauth2-jwt-secret
6. gitea-metrics-token
7. gitea-runner-token (placeholder - update after deployment)
8. namecheap-api-key (if env var set)
9. namecheap-api-user (if env var set)
10. namecheap-api-ip (if env var set)

**Step 4: Configure Backend**
```bash
cd ../terraform/gcp-gitea

# Get bucket name from bootstrap output
BUCKET_NAME=$(cd bootstrap && terraform output -raw state_bucket_name)

# Configure backend.tf
cp backend.tf.template backend.tf
sed -i "s/REPLACE_WITH_BUCKET_NAME/${BUCKET_NAME}/" backend.tf
```

**Step 5: Deploy Infrastructure**
```bash
terraform init
terraform plan
terraform apply
```

Expected Resources:
- VPC network with subnet
- Cloud NAT and Cloud Router
- Firewall rules (3)
- Cloud Armor security policy
- Compute Engine instance
- Persistent disks (2)
- GCS buckets (3: evidence, backup, logs)
- KMS crypto keys
- Uptime checks (2)
- Alert policies (4)
- Monitoring dashboard

**Step 6: Post-Deployment**
```bash
# Get instance IP
terraform output instance_ip

# SSH to instance (via IAP)
gcloud compute ssh gitea-instance \
  --project=cui-gitea-prod \
  --zone=us-central1-a \
  --tunnel-through-iap

# Verify services
docker compose -f /home/gitea/docker-compose.gcp.yml ps

# Update DNS A record
# gitea.cui-secure.us -> INSTANCE_IP

# Wait for SSL certificate (Caddy auto-generates Let's Encrypt)

# Access Gitea
# https://gitea.cui-secure.us

# Update gitea-runner-token from Gitea UI
# Settings > Actions > Runners > Create Runner > Copy token
gcloud secrets versions add gitea-runner-token \
  --data-file=- \
  --project=cui-gitea-prod
```

### 5.3 Deployment Timeline

| Phase | Duration | Status |
|-------|----------|--------|
| Project Creation | 2 minutes | ✓ Complete |
| API Enablement | 1 minute | ✓ Complete |
| Configuration | 5 minutes | ✓ Complete |
| Bootstrap | 3 minutes | Pending |
| Secret Creation | 2 minutes | Pending |
| Infrastructure Deploy | 15 minutes | Pending |
| SSL Certificate | 5 minutes | Pending |
| Post-Config | 10 minutes | Pending |
| **Total** | **~45 minutes** | **In Progress** |

---

## 6. Cost Estimate

**Monthly Cost Breakdown** (us-central1):

| Component | Specification | Monthly Cost (USD) |
|-----------|--------------|-------------------|
| Compute Engine | e2-standard-8, always-on | $195 |
| Boot Disk | 200GB SSD | $34 |
| Data Disk | 500GB SSD | $85 |
| GCS Buckets | 3 buckets, minimal usage | $10 |
| Cloud KMS | 3 keys + operations | $3 |
| Secret Manager | 10 secrets | $0.18 |
| Static IP | 1 IP address | $7 |
| Cloud NAT | Gateway + data processing | $45 |
| Network Egress | ~10GB/month | $1.20 |
| Cloud Monitoring | Basic metrics + alerts | $0 |
| Cloud Logging | Audit logs ingestion | $5 |
| **TOTAL** | | **~$385/month** |

**Notes**:
- Costs include sustained use discounts
- Actual costs vary based on usage patterns
- Cross-region replication disabled (save ~$50/month)
- Evidence retention (7 years) adds ~$2/month for 100GB

---

## 7. Evidence Artifacts

**For Compliance Assessors**:

### 7.1 Project Creation Evidence
```json
{
  "timestamp": "2025-10-07T23:15:00Z",
  "project_id": "cui-gitea-prod",
  "project_number": "1018248415137",
  "organization_id": "1024722247064",
  "billing_account": "01B48D-9AF35D-EC356C",
  "billing_enabled": true,
  "apis_enabled": 9,
  "created_by": "nmartin@dcg.cui-secure.us"
}
```

### 7.2 Bootstrap Evidence
Location: `terraform/gcp-gitea/bootstrap/evidence/bootstrap_complete_*.json`

### 7.3 Secrets Evidence
Location: `terraform/gcp-gitea/evidence/secrets_created_*.json`

### 7.4 Deployment Evidence
Location: `terraform/gcp-gitea/evidence/deployment_*.json`

### 7.5 Audit Logs
Location: `gs://cui-gitea-prod-prod-audit-*/logs/`
- State changes (7-year retention)
- Secret access logs (7-year retention)
- Infrastructure modifications (7-year retention)

---

## 8. Operational Contacts

**Primary Operator**: nmartin@dcg.cui-secure.us
**Organization**: DCG (dcg.cui-secure.us)
**Alert Email**: nmartin@dcg.cui-secure.us
**Project Owner**: DCG Platform Team
**Compliance Officer**: [TBD]
**Security Officer**: [TBD]

---

## 9. References

- **Terraform Configurations**: `/home/notme/Desktop/gitea/terraform/gcp-gitea/`
- **Deployment Scripts**: `/home/notme/Desktop/gitea/scripts/`
- **State Management Guide**: `/home/notme/Desktop/gitea/docs/STATE_MANAGEMENT.md`
- **GCP Deployment Guide**: `/home/notme/Desktop/gitea/docs/GCP_DEPLOYMENT_GUIDE.md`
- **Operations Runbook**: `/home/notme/Desktop/gitea/docs/GCP_OPERATIONS_RUNBOOK.md`
- **Disaster Recovery**: `/home/notme/Desktop/gitea/docs/GCP_DISASTER_RECOVERY.md`

---

## 10. Deployment Status

**Current Status**: Pre-Deployment (Bootstrap Pending)

**Completed**:
- ✓ GCP Project Creation
- ✓ API Enablement
- ✓ Configuration Updates
- ✓ Documentation

**Pending**:
- [ ] Application Default Credentials
- [ ] Bootstrap Execution
- [ ] Secret Creation
- [ ] Infrastructure Deployment
- [ ] Post-Deployment Verification

**Next Action**: Execute deployment sequence starting with ADC setup

---

**Document Version**: 1.0
**Last Updated**: 2025-10-07T23:20:00Z
**Maintained By**: DCG Platform Team
**Classification**: Internal / Compliance Record
