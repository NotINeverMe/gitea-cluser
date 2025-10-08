# Terraform State Management Guide

**Secure, Compliant Infrastructure State Management for CMMC 2.0 Level 2**

This guide describes the complete state management system for the Gitea GCP deployment, including Terraform state backend, Secret Manager integration, versioning, backup/recovery procedures, and compliance mappings.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Bootstrap Procedure](#bootstrap-procedure)
4. [Secret Management](#secret-management)
5. [State Backend Configuration](#state-backend-configuration)
6. [State Backup and Recovery](#state-backup-and-recovery)
7. [Configuration Versioning](#configuration-versioning)
8. [Security Best Practices](#security-best-practices)
9. [Troubleshooting](#troubleshooting)
10. [Compliance Mapping](#compliance-mapping)

---

## Overview

### Design Goals

The state management system is designed to meet the following requirements:

1. **Zero Secrets in Code**: All credentials stored in Secret Manager, never in Terraform code or state
2. **Immutable Audit Trail**: 7-year retention of state changes for CMMC compliance
3. **Complete Redeployability**: Deploy from any machine using GCS backend + Secret Manager
4. **State Recovery**: Point-in-time recovery from versioned GCS backups
5. **Configuration Rollback**: Revert to previous terraform.tfvars versions
6. **Encryption at Rest**: CMEK encryption for all state and configuration data
7. **Least Privilege Access**: IAM-based access with service accounts

### Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Terraform State Management                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────┐ │
│  │   GCS Backend    │     │ Secret Manager   │     │  Cloud KMS   │ │
│  │                  │     │                  │     │              │ │
│  │ • State storage  │────▶│ • Passwords      │────▶│ • CMEK keys  │ │
│  │ • 30 versions    │     │ • API keys       │     │ • 90d rotate │ │
│  │ • State locking  │     │ • Tokens         │     │ • Audit log  │ │
│  └──────────────────┘     └──────────────────┘     └──────────────┘ │
│           │                        │                        │         │
│           │                        │                        │         │
│           ▼                        ▼                        ▼         │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Audit & Evidence Collection                     │   │
│  │  • State change logs (7-year retention)                      │   │
│  │  • Configuration versions (GCS)                              │   │
│  │  • Secret access logs (Cloud Logging)                        │   │
│  │  • Evidence JSON with SHA256 checksums                       │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Architecture

### Storage Architecture

```
GCS Buckets:
  vipr-dcg-prod-tfstate-XXXXXX/
    ├── terraform/state/
    │   └── default.tfstate          # Terraform state (30 versions retained)
    └── terraform/configs/
        └── terraform.tfvars         # Configuration (versioned)

  vipr-dcg-prod-audit-XXXXXX/
    └── logs/
        ├── tfstate-changes.json     # State modification audit (7 years)
        └── secret-access.json       # Secret access audit (7 years)
```

### Secret Manager Structure

```
Secret Manager:
  gitea-admin-password              # Gitea admin account
  postgres-password                 # PostgreSQL database
  gitea-secret-key                  # Session encryption
  gitea-internal-token              # Internal API auth
  gitea-oauth2-jwt-secret           # OAuth2 JWT signing
  gitea-metrics-token               # Prometheus metrics
  gitea-runner-token                # Actions runner (update post-deploy)
  namecheap-api-key                 # DNS automation
  namecheap-api-user                # DNS automation
  namecheap-api-ip                  # DNS automation
```

### Service Accounts

```
IAM Service Accounts:
  vipr-dcg-terraform-deployer       # CI/CD deployments
  vipr-dcg-gitea-vm                 # VM operations
  vipr-dcg-evidence-collector       # Compliance automation
  vipr-dcg-backup                   # Backup operations
```

---

## Bootstrap Procedure

### Prerequisites

1. **GCP Project**: `vipr-dcg` with billing enabled
2. **Required APIs**: Compute Engine, Cloud Storage, Cloud KMS, Secret Manager, Cloud Logging, Cloud Monitoring
3. **Authentication**: `gcloud auth application-default login`
4. **Terraform**: Version 1.5.0 or later

### Step 1: Bootstrap State Backend

The bootstrap process creates the foundational infrastructure for state management.

```bash
cd terraform/gcp-gitea/bootstrap

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars
nano terraform.tfvars
```

**terraform.tfvars**:
```hcl
project_id          = "vipr-dcg"
region              = "us-central1"
environment         = "prod"
kms_location        = "us-central1"
bucket_location     = "US"
terraform_sa_email  = ""  # Leave empty - created in main Terraform
```

**Deploy bootstrap**:
```bash
terraform init
terraform plan
terraform apply
```

**Bootstrap creates**:
- GCS state bucket with versioning (30 versions retained)
- GCS audit bucket with 7-year retention
- Cloud KMS keyring with 3 keys (state, storage, secrets)
- Log sink for state change audit
- IAM bindings for service accounts

**Save outputs**:
```bash
terraform output -json > bootstrap-outputs.json
```

### Step 2: Create Secrets

Generate and store all credentials in Secret Manager.

```bash
cd ../../scripts

# Create secrets
./create-secrets.sh -p vipr-dcg -r us-central1

# Verify secrets created
gcloud secrets list --project=vipr-dcg
```

**Generated secrets**:
- 10 secrets with secure random passwords/tokens
- Regional replication (us-central1)
- CMMC compliance labels (`cmmc=ia-l2-3-5-1`)
- Evidence JSON with creation timestamps

**Post-creation**:
```bash
# Update gitea-runner-token after Gitea deployment
gcloud secrets versions add gitea-runner-token \
  --data-file=- \
  --project=vipr-dcg
# (Paste token from Gitea UI)
```

### Step 3: Configure Backend

Create `backend.tf` using the bucket name from bootstrap output.

```bash
cd ../terraform/gcp-gitea

# Copy template
cp backend.tf.template backend.tf

# Edit with bucket name from bootstrap output
BUCKET_NAME=$(jq -r '.state_bucket.value' ../bootstrap/bootstrap-outputs.json)
sed -i "s/REPLACE_WITH_BUCKET_NAME/${BUCKET_NAME}/" backend.tf
```

**backend.tf**:
```hcl
terraform {
  backend "gcs" {
    bucket = "vipr-dcg-prod-tfstate-1234567890"
    prefix = "terraform/state"
  }
}
```

### Step 4: Initialize Main Terraform

```bash
terraform init

# Migrate local state to GCS (if exists)
# terraform init -migrate-state

terraform plan
terraform apply
```

---

## Secret Management

### Secret Lifecycle

1. **Creation**: `create-secrets.sh` generates secure random passwords
2. **Storage**: Secret Manager with regional replication and CMEK encryption
3. **Access**: Service accounts with `secretmanager.secretAccessor` role
4. **Rotation**: Manual rotation recommended every 90 days
5. **Audit**: All access logged to Cloud Logging (7-year retention)

### Retrieving Secrets

**List all secrets**:
```bash
gcloud secrets list --project=vipr-dcg
```

**Access secret value**:
```bash
gcloud secrets versions access latest \
  --secret=gitea-admin-password \
  --project=vipr-dcg
```

**Access from VM** (uses service account):
```bash
# On Gitea VM
gcloud secrets versions access latest \
  --secret=gitea-admin-password
```

### Rotating Secrets

**Generate new password**:
```bash
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-24)
```

**Add new version**:
```bash
echo -n "${NEW_PASSWORD}" | gcloud secrets versions add gitea-admin-password \
  --data-file=- \
  --project=vipr-dcg
```

**Update application**:
```bash
# SSH to VM
gcloud compute ssh gitea-instance --project=vipr-dcg --zone=us-central1-a

# Update secret file
echo -n "${NEW_PASSWORD}" | sudo tee /run/secrets/admin_password

# Restart Gitea
cd /home/gitea && docker compose restart gitea
```

**Disable old version**:
```bash
gcloud secrets versions disable 1 \
  --secret=gitea-admin-password \
  --project=vipr-dcg
```

### Secret Rotation Schedule

| Secret                     | Rotation Frequency | CMMC Control  |
|----------------------------|--------------------|---------------|
| gitea-admin-password       | 90 days            | IA.L2-3.5.1   |
| postgres-password          | 90 days            | IA.L2-3.5.1   |
| gitea-secret-key           | 180 days           | SC.L2-3.13.11 |
| gitea-internal-token       | 180 days           | IA.L2-3.5.1   |
| gitea-oauth2-jwt-secret    | 180 days           | SC.L2-3.13.11 |
| gitea-metrics-token        | 90 days            | IA.L2-3.5.1   |
| gitea-runner-token         | On compromise      | IA.L2-3.5.1   |
| namecheap-api-key          | On compromise      | IA.L2-3.5.1   |

---

## State Backend Configuration

### GCS Backend Features

- **Versioning**: 30 versions retained, older versions auto-deleted
- **State Locking**: Built-in via GCS object versioning
- **Encryption**: CMEK using Cloud KMS `tfstate-encryption-key`
- **Audit Logging**: All state modifications logged to audit bucket
- **Access Control**: IAM-based with service account conditions

### State File Structure

```json
{
  "version": 4,
  "terraform_version": "1.12.2",
  "serial": 42,
  "lineage": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "outputs": { ... },
  "resources": [
    {
      "mode": "managed",
      "type": "google_compute_instance",
      "name": "gitea",
      "provider": "provider[\"registry.terraform.io/hashicorp/google\"]",
      "instances": [ ... ]
    }
  ]
}
```

### State Operations

**View current state**:
```bash
terraform state list
terraform state show google_compute_instance.gitea
```

**Pull remote state**:
```bash
terraform state pull > local-state.json
```

**Refresh state** (sync with real infrastructure):
```bash
terraform refresh
```

**Remove resource from state**:
```bash
terraform state rm google_compute_instance.gitea
```

**Import existing resource**:
```bash
terraform import google_compute_instance.gitea \
  projects/vipr-dcg/zones/us-central1-a/instances/gitea-instance
```

---

## State Backup and Recovery

### Automatic Backups

GCS versioning provides automatic state backups:
- **Retention**: 30 versions (approximately 30 deployments)
- **Storage**: Encrypted with CMEK
- **Lifecycle**: Automatic cleanup of older versions

### Listing State Versions

```bash
cd scripts

./gcp-state-recovery.sh \
  -p vipr-dcg \
  -b vipr-dcg-prod-tfstate-1234567890 \
  -l
```

**Output**:
```
Available Terraform State Versions:

NAME                                    GENERATION    TIME CREATED              SIZE
default.tfstate                         1234567890    2025-10-07T10:30:00Z      245KB
default.tfstate                         1234567889    2025-10-06T15:20:00Z      243KB
default.tfstate                         1234567888    2025-10-05T09:10:00Z      240KB

Total versions: 30
```

### Recovering State

**Interactive recovery** (prompts for confirmation):
```bash
./gcp-state-recovery.sh \
  -p vipr-dcg \
  -b vipr-dcg-prod-tfstate-1234567890 \
  -v 1234567889
```

**Force recovery** (no confirmation):
```bash
./gcp-state-recovery.sh \
  -p vipr-dcg \
  -b vipr-dcg-prod-tfstate-1234567890 \
  -v 1234567889 \
  -f
```

**Dry-run** (preview without applying):
```bash
./gcp-state-recovery.sh \
  -p vipr-dcg \
  -b vipr-dcg-prod-tfstate-1234567890 \
  -v 1234567889 \
  -d
```

**Recovery process**:
1. Downloads specified state version from GCS
2. Validates JSON syntax
3. Backs up current state to `.state-backups/`
4. Restores selected version
5. Calculates SHA256 checksum
6. Generates recovery evidence JSON

**Post-recovery verification**:
```bash
cd ../terraform/gcp-gitea

# Verify state integrity
terraform plan

# Refresh state to sync with infrastructure
terraform refresh

# Check for drift
terraform plan
```

### Recovery Scenarios

**Scenario 1: Accidental state corruption**
```bash
# Recover to last known good state
./gcp-state-recovery.sh -p vipr-dcg -b BUCKET_NAME -v GOOD_VERSION

# Verify recovery
cd ../terraform/gcp-gitea && terraform plan
```

**Scenario 2: Rollback after failed deployment**
```bash
# Recover state before failed apply
./gcp-state-recovery.sh -p vipr-dcg -b BUCKET_NAME -v PRE_DEPLOYMENT_VERSION

# Rollback configuration
./gcp-config-rollback.sh -p vipr-dcg -b BUCKET_NAME -v PRE_DEPLOYMENT_VERSION

# Re-plan deployment
cd ../terraform/gcp-gitea && terraform plan
```

**Scenario 3: State lost locally**
```bash
# Fresh checkout - state already in GCS
cd terraform/gcp-gitea
terraform init  # Automatically pulls state from GCS
terraform plan  # Verify state matches infrastructure
```

---

## Configuration Versioning

### Configuration Backup

Upload `terraform.tfvars` to GCS for versioning:

```bash
cd terraform/gcp-gitea

# Upload current config
gcloud storage cp terraform.tfvars \
  "gs://vipr-dcg-prod-tfstate-1234567890/terraform/configs/terraform.tfvars" \
  --project=vipr-dcg

# Add metadata
gcloud storage objects update \
  "gs://vipr-dcg-prod-tfstate-1234567890/terraform/configs/terraform.tfvars" \
  --custom-metadata=config_version="1.0.0",deployed_by="$(whoami)",deployed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --project=vipr-dcg
```

### Listing Configuration Versions

```bash
cd scripts

./gcp-config-rollback.sh \
  -p vipr-dcg \
  -b vipr-dcg-prod-tfstate-1234567890 \
  -l
```

### Rolling Back Configuration

**Interactive rollback**:
```bash
./gcp-config-rollback.sh \
  -p vipr-dcg \
  -b vipr-dcg-prod-tfstate-1234567890 \
  -v 1234567889
```

**Rollback process**:
1. Downloads specified config version from GCS
2. Validates syntax (checks for hardcoded secrets)
3. Runs `terraform validate`
4. Backs up current config to `.config-backups/`
5. Restores selected version
6. Generates rollback evidence JSON with diff

**Post-rollback**:
```bash
cd ../terraform/gcp-gitea

# Review changes
terraform plan

# Apply if desired
terraform apply
```

---

## Security Best Practices

### 1. Secret Management

- ✅ **DO**: Store all credentials in Secret Manager
- ✅ **DO**: Use service accounts for application access
- ✅ **DO**: Rotate secrets every 90 days
- ✅ **DO**: Enable audit logging for secret access
- ❌ **DON'T**: Hardcode secrets in Terraform code
- ❌ **DON'T**: Store secrets in environment variables
- ❌ **DON'T**: Share secrets via email or chat

### 2. State File Protection

- ✅ **DO**: Use GCS backend with CMEK encryption
- ✅ **DO**: Enable versioning (30 versions minimum)
- ✅ **DO**: Restrict IAM access to state bucket
- ✅ **DO**: Enable audit logging for state modifications
- ❌ **DON'T**: Store state files in version control
- ❌ **DON'T**: Use local state in production
- ❌ **DON'T**: Grant public access to state bucket

### 3. Access Control

- ✅ **DO**: Use service accounts with least privilege
- ✅ **DO**: Enable IAM conditions for time/IP restrictions
- ✅ **DO**: Use OS Login for SSH access
- ✅ **DO**: Enable Identity-Aware Proxy (IAP)
- ❌ **DON'T**: Use personal accounts for automation
- ❌ **DON'T**: Grant Owner role to service accounts
- ❌ **DON'T**: Allow direct SSH from internet

### 4. Audit and Compliance

- ✅ **DO**: Retain audit logs for 7 years (CMMC requirement)
- ✅ **DO**: Generate evidence JSON for all operations
- ✅ **DO**: Calculate SHA256 checksums for integrity
- ✅ **DO**: Document all state recoveries and rollbacks
- ❌ **DON'T**: Delete audit logs prematurely
- ❌ **DON'T**: Modify evidence files after creation
- ❌ **DON'T**: Skip evidence generation

### 5. Disaster Recovery

- ✅ **DO**: Test recovery procedures quarterly
- ✅ **DO**: Maintain offline backups of critical state
- ✅ **DO**: Document recovery runbooks
- ✅ **DO**: Practice incident response scenarios
- ❌ **DON'T**: Assume backups work without testing
- ❌ **DON'T**: Skip DR testing in production

---

## Troubleshooting

### State Locked

**Problem**: `Error: Error acquiring the state lock`

**Cause**: Previous Terraform operation crashed or is still running

**Solution**:
```bash
# Check for running Terraform processes
ps aux | grep terraform

# Force unlock (use with caution)
terraform force-unlock LOCK_ID

# Or wait for automatic timeout (typically 10 minutes)
```

### Secret Not Found

**Problem**: `Error: google_secret_manager_secret_version.admin_password: resource not found`

**Cause**: Secret not created or incorrect project ID

**Solution**:
```bash
# Verify secret exists
gcloud secrets list --project=vipr-dcg

# Create missing secret
cd scripts
./create-secrets.sh -p vipr-dcg -r us-central1
```

### State Version Mismatch

**Problem**: `Error: state snapshot was created by Terraform v1.10.0, but this is v1.12.2`

**Cause**: Terraform version downgrade

**Solution**:
```bash
# Upgrade Terraform to match or newer version
terraform version

# Or recover from older state version
cd scripts
./gcp-state-recovery.sh -p vipr-dcg -b BUCKET_NAME -l
# Select version created with compatible Terraform version
```

### Permission Denied

**Problem**: `Error: googleapi: Error 403: Permission denied on resource`

**Cause**: Insufficient IAM permissions

**Solution**:
```bash
# Check current authenticated user
gcloud auth list

# Verify permissions
gcloud projects get-iam-policy vipr-dcg \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"

# Request necessary roles from project owner
```

### State Drift Detected

**Problem**: `terraform plan` shows changes when none were made

**Cause**: Manual changes outside Terraform or resource recreation

**Solution**:
```bash
# Refresh state to sync with current infrastructure
terraform refresh

# Review changes
terraform plan

# Import manually created resources
terraform import google_compute_instance.gitea \
  projects/vipr-dcg/zones/us-central1-a/instances/gitea-instance
```

---

## Compliance Mapping

### CMMC 2.0 Level 2 Controls

| Control | Requirement | Implementation |
|---------|-------------|----------------|
| **AC.L2-3.1.1** | Authorized Access Control | IAM service accounts with least privilege, OS Login enabled |
| **AU.L2-3.3.1** | Audit Logging | 7-year retention of state changes, secret access logs |
| **AU.L2-3.3.8** | Audit Record Protection | Immutable audit bucket, versioning enabled, CMEK encryption |
| **CM.L2-3.4.2** | Baseline Configuration | Versioned terraform.tfvars, state versioning, rollback capability |
| **CP.L2-3.11.1** | Information Backup | 30 state versions, automated backups, cross-region DR option |
| **IA.L2-3.5.1** | Identification & Authentication | Secret Manager for credentials, service account authentication |
| **IA.L2-3.5.7** | Cryptographic Protection | CMEK encryption for state, secrets, and audit logs |
| **SC.L2-3.13.11** | Cryptographic Protection | KMS keys with 90-day rotation, encryption at rest |
| **SI.L2-3.14.1** | System Monitoring | Cloud Logging for state operations, alert on modifications |

### NIST SP 800-171 Rev. 2

| Section | Requirement | Implementation |
|---------|-------------|----------------|
| **§3.1.1** | Access Control | IAM policies with least privilege, MFA for admin access |
| **§3.3.1** | Audit Records | Comprehensive logging of state and secret operations |
| **§3.3.8** | Audit Protection | Immutable audit logs with 7-year retention |
| **§3.4.2** | Configuration Baselines | Versioned state and configuration files |
| **§3.5.1** | Authenticator Management | Secret Manager with rotation policies |
| **§3.5.7** | Password Obscuration | Secrets never in code, encrypted in transit and at rest |
| **§3.11.1** | Information Backups | Automated state versioning and backup procedures |
| **§3.13.11** | Cryptographic Key Management | KMS-managed keys with automatic rotation |
| **§3.14.1** | Flaw Remediation | State recovery enables quick rollback of issues |

### Evidence Artifacts

**For Assessors**:

1. **Bootstrap Evidence**:
   - `terraform/gcp-gitea/bootstrap/evidence/bootstrap_complete_*.json`
   - State bucket creation timestamp
   - KMS key configuration
   - Audit log sink setup

2. **Secret Creation Evidence**:
   - `terraform/gcp-gitea/evidence/secrets_created_*.json`
   - List of secrets created
   - Creation timestamps
   - CMMC control mappings

3. **State Recovery Evidence**:
   - `terraform/gcp-gitea/evidence/state_recovery_*.json`
   - Recovery timestamps
   - Version restored
   - SHA256 checksums

4. **Configuration Rollback Evidence**:
   - `terraform/gcp-gitea/evidence/config_rollback_*.json`
   - Rollback timestamps
   - Configuration diff
   - Validation results

5. **Audit Logs**:
   - `gs://vipr-dcg-prod-audit-*/logs/tfstate-changes.json`
   - All state modifications (7-year retention)
   - Operator identity, timestamp, operation type

---

## References

- **Terraform Documentation**: https://www.terraform.io/docs
- **Google Cloud Terraform Provider**: https://registry.terraform.io/providers/hashicorp/google/latest/docs
- **Secret Manager Best Practices**: https://cloud.google.com/secret-manager/docs/best-practices
- **CMMC 2.0 Assessment Guide**: https://www.acq.osd.mil/cmmc/
- **NIST SP 800-171 Rev. 2**: https://csrc.nist.gov/publications/detail/sp/800-171/rev-2/final

---

## Support

For questions or issues with state management:

1. Check this documentation
2. Review Terraform logs: `TF_LOG=DEBUG terraform apply`
3. Check Cloud Logging: https://console.cloud.google.com/logs/query?project=vipr-dcg
4. Review evidence artifacts in `terraform/gcp-gitea/evidence/`
5. Contact: nmartin@dcg.cui-secure.us

---

**Document Version**: 1.0
**Last Updated**: 2025-10-07
**Maintained By**: DCG Platform Team
**Compliance**: CMMC 2.0 Level 2, NIST SP 800-171 Rev. 2
