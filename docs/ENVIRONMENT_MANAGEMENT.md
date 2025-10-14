# Environment Management Guide
## DCG Gitea Infrastructure - Multi-Environment Operations

**Document Version**: 1.0
**Created**: 2025-10-13
**Last Updated**: 2025-10-13
**Status**: ACTIVE
**Compliance**: CMMC 2.0 Level 2, NIST SP 800-171 Rev. 2

---

## Purpose

This guide establishes comprehensive procedures for managing multiple Gitea infrastructure environments to prevent configuration errors, accidental resource modifications, and ensure clear environment isolation. These procedures are mandatory for all infrastructure operations.

**Critical Principle**: *"Explicit is Better Than Implicit"* - Always specify exactly which environment you're working with.

---

## Table of Contents

1. [Environment Overview](#environment-overview)
2. [Environment Isolation Strategy](#environment-isolation-strategy)
3. [Configuration File Structure](#configuration-file-structure)
4. [Environment Switching Procedures](#environment-switching-procedures)
5. [Variable File Naming Conventions](#variable-file-naming-conventions)
6. [Common Workflows](#common-workflows)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)
9. [Incident Prevention](#incident-prevention)

---

## Environment Overview

### Active Environments

| Environment | Project ID | Status | Purpose | Risk Level | Monthly Cost |
|-------------|-----------|--------|---------|------------|--------------|
| **Development** | dcg-gitea-dev | PLANNED | Testing, experimentation, development | LOW | ~$200 |
| **Staging** | dcg-gitea-stage | ACTIVE | Pre-production validation, testing | MEDIUM | ~$300 |
| **Production** | cui-gitea-prod | DECOMMISSIONED | Former production system | N/A | $0 |

### Environment Details

#### Development Environment (`dcg-gitea-dev`)
- **Status**: Planned (not yet deployed)
- **Purpose**: Developer testing, feature development, breaking changes
- **Machine Type**: e2-standard-2 (cost-optimized)
- **Disk Size**: 100GB boot + 100GB data
- **Data Classification**: Test data only
- **Retention**: Minimal (7 days for backups, 30 days for evidence)
- **Deletion Protection**: Disabled
- **Operations**: Full access, no approval required

#### Staging Environment (`dcg-gitea-stage`)
- **Status**: Active
- **Purpose**: Pre-production validation, integration testing
- **Machine Type**: e2-standard-4 (production-like)
- **Disk Size**: 100GB boot + 200GB data
- **Data Classification**: Non-CUI test data
- **Retention**: 7 days for backups, 2555 days for evidence (CMMC requirement)
- **Deletion Protection**: Enabled on critical resources
- **Operations**: Requires review for destructive changes

#### Production Environment (`cui-gitea-prod`)
- **Status**: DECOMMISSIONED as of 2025-10-13
- **Purpose**: Historical reference only
- **Important**: Do NOT deploy to this project
- **Evidence**: Retained in compliance buckets for 7-year CMMC requirement
- **Configuration**: Maintained in `terraform.tfvars.prod` for reference only

### Environment Use Cases

**When to use Development:**
- Testing new Terraform modules
- Experimenting with configuration changes
- Breaking changes that need validation
- Developer feature testing
- Quick iterations without risk

**When to use Staging:**
- Final validation before production release
- Integration testing with production-like configuration
- Performance testing under load
- Security scanning and compliance validation
- Client demonstrations (non-CUI data only)

**When NOT to use Production:**
- cui-gitea-prod is decommissioned - do not use

---

## Environment Isolation Strategy

### Why Environment Isolation Matters

**Real-world incident: The dcg-gitea-stage Accident (October 13, 2025)**

**What happened:**
1. Operator was working on decommissioning cui-gitea-prod (production)
2. Generated a destroy plan for production using `terraform plan -destroy -var-file=terraform.tfvars.prod`
3. Terraform backend was initialized to dcg-gitea-stage state bucket
4. GCloud context showed cui-gitea-prod
5. Variable file specified cui-gitea-prod
6. BUT: Terraform backend configuration in `backend.tf` was hardcoded to dcg-gitea-stage
7. Result: Destroyed all resources in dcg-gitea-stage (wrong environment)
8. Impact: 86 resources destroyed, 4 hours of recovery time

**Root causes:**
- Terraform backend (`backend.tf`) was not reconfigured when switching projects
- Reliance on gcloud project setting alone (which doesn't affect Terraform backend)
- terraform.tfvars was auto-loaded without explicit -var-file parameter
- Multiple sources of truth (gcloud, backend.tf, .tfvars) were not aligned

**Lessons learned:**
1. Always verify Terraform backend matches intended environment
2. Never rely on gcloud config alone
3. Always use explicit -var-file parameter
4. Run validation scripts before any destructive operation
5. Understand that Terraform has its own state management separate from gcloud

### Three Contexts That Must Align

Terraform operations depend on THREE separate configurations that must all match:

```
┌─────────────────────────────────────────────────────────────┐
│  CONTEXT 1: GCloud Configuration                            │
│  Command: gcloud config get-value project                   │
│  Purpose: GCP API authentication and authorization          │
│  File: ~/.config/gcloud/configurations/config_default       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  CONTEXT 2: Terraform Backend                               │
│  File: terraform/gcp-gitea/backend.tf                       │
│  Purpose: Where Terraform state is stored (GCS bucket)      │
│  Critical: This determines which environment state is used  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  CONTEXT 3: Terraform Variables                             │
│  File: terraform.tfvars.{environment}                       │
│  Purpose: Configuration values (project_id, region, etc.)   │
│  Must be specified explicitly with -var-file parameter      │
└─────────────────────────────────────────────────────────────┘
```

**All three must point to the same environment for safe operations.**

### How .env Files Work

Environment-specific `.env` files provide a single source of truth for shell operations:

```bash
# File: .env.staging
PROJECT_ID="dcg-gitea-stage"
ENVIRONMENT="staging"
REGION="us-central1"
ZONE="us-central1-a"
VAR_FILE="terraform.tfvars.staging"
TF_VAR_project_id="dcg-gitea-stage"
TF_VAR_environment="staging"
```

**To activate an environment:**
```bash
# Source the environment file
source .env.staging

# This sets all environment variables for this shell session
echo $PROJECT_ID  # dcg-gitea-stage
echo $VAR_FILE    # terraform.tfvars.staging
```

**Important limitations:**
- .env files only affect the current shell session
- They do NOT modify terraform backend.tf
- They do NOT change gcloud default project
- They provide variables for scripts but not Terraform directly

### How terraform.tfvars.{env} Prevents Auto-Loading Issues

**The Problem with terraform.tfvars:**
```bash
# If terraform.tfvars exists in working directory:
terraform plan    # Automatically loads terraform.tfvars
                  # You don't know which environment it's configured for!
```

**The Solution - Environment-Specific Naming:**
```bash
# No terraform.tfvars file exists (it's gitignored)
# Instead, we have:
terraform.tfvars.dev      # Development configuration
terraform.tfvars.staging  # Staging configuration
terraform.tfvars.prod     # Production configuration (decommissioned reference)

# Must specify explicitly:
terraform plan -var-file=terraform.tfvars.staging   # Clear and obvious
```

**Benefits:**
1. No ambiguity about which environment
2. Forces explicit environment selection
3. Command clearly shows target environment
4. Prevents accidental cross-environment operations
5. Self-documenting in command history

---

## Configuration File Structure

### Directory Layout

```
/home/notme/Desktop/code/DCG/gitea/
├── .env.dev              # Development environment variables
├── .env.staging          # Staging environment variables
├── .env.prod             # Production environment variables (decommissioned)
├── .env.example          # Template for new environments
├── terraform/
│   └── gcp-gitea/
│       ├── backend.tf                    # Terraform state configuration (environment-specific)
│       ├── terraform.tfvars              # Current working config (gitignored)
│       ├── terraform.tfvars.dev          # Development configuration
│       ├── terraform.tfvars.staging      # Staging configuration
│       ├── terraform.tfvars.prod         # Production configuration (reference only)
│       └── terraform.tfvars.example      # Template with documentation
└── scripts/
    ├── terraform-project-validator.sh    # Validates all three contexts
    ├── pre-destroy-validator.sh          # Pre-destruction safety checks
    └── gcp-destroy.sh                    # Safe destruction wrapper
```

### .env File Purpose and Contents

**.env files provide:**
- Shell environment variables for scripts
- Documentation of environment configuration
- Single source of truth for automation
- Quick environment reference

**Example .env.staging:**
```bash
# Staging Environment Configuration
# Project: DCG Gitea Staging
PROJECT_ID="dcg-gitea-stage"
ENVIRONMENT="staging"
REGION="us-central1"
ZONE="us-central1-a"
VAR_FILE="terraform.tfvars.staging"
TF_VAR_project_id="dcg-gitea-stage"
TF_VAR_environment="staging"
```

**Key variables explained:**
- `PROJECT_ID`: GCP project identifier (for gcloud commands)
- `ENVIRONMENT`: Environment name (dev/staging/prod)
- `REGION`: GCP region for resources
- `ZONE`: GCP zone for compute instances
- `VAR_FILE`: Which terraform.tfvars.{env} file to use
- `TF_VAR_*`: Direct Terraform variable overrides

### terraform.tfvars.{env} File Purpose

**These files contain actual infrastructure configuration:**
- Project ID and region settings
- Machine types and disk sizes
- Network configuration
- Security settings
- Monitoring and alerting config
- Retention policies
- Resource labels

**Example terraform.tfvars.staging (partial):**
```hcl
project_id = "dcg-gitea-stage"
environment = "staging"
region = "us-central1"
zone = "us-central1-a"

machine_type = "e2-standard-4"
boot_disk_size = 100
data_disk_size = 200

gitea_domain = "git-stage.dcg.cui-secure.us"
gitea_admin_email = "nmartin@dcg.cui-secure.us"

evidence_retention_days = 2555
backup_retention_days = 7
```

### Relationship Between .env and .tfvars Files

```
┌──────────────────────┐           ┌───────────────────────────┐
│  .env.staging        │  Maps to  │  terraform.tfvars.staging │
├──────────────────────┤───────────├───────────────────────────┤
│ PROJECT_ID=          │           │ project_id =              │
│ "dcg-gitea-stage"    │ ────────> │ "dcg-gitea-stage"         │
│                      │           │                           │
│ VAR_FILE=            │           │ environment =             │
│ "terraform.tfvars... │ ────────> │ "staging"                 │
│                      │           │                           │
│ ENVIRONMENT=         │           │ machine_type =            │
│ "staging"            │           │ "e2-standard-4"           │
└──────────────────────┘           └───────────────────────────┘
     Shell Variables                  Terraform Variables
     (for scripts)                    (for infrastructure)
```

**Important:** These files should always agree on project_id and environment!

### What to Track in Git

```bash
# Tracked in Git (committed):
.env.example                    # Template
terraform.tfvars.example        # Template with documentation
terraform.tfvars.dev            # Development config
terraform.tfvars.staging        # Staging config
terraform.tfvars.prod           # Production config (reference)

# NOT tracked in Git (gitignored):
.env.local                      # Local overrides
terraform.tfvars                # Working copy (ambiguous)
*.tfstate                       # Terraform state (in GCS)
*.tfstate.backup                # State backups
.terraform/                     # Terraform working directory
backend.tf.local                # Local backend overrides
```

**Rationale:**
- Environment-specific configs are shared with team
- Local working copies may have sensitive data
- State files belong in remote backend (GCS)
- Local overrides are operator-specific

---

## Environment Switching Procedures

### Pre-Switch Verification

**Always verify your CURRENT environment before switching:**

```bash
# Check all three contexts
echo "1. GCloud Project:"
gcloud config get-value project

echo "2. Terraform Backend:"
grep bucket terraform/gcp-gitea/backend.tf

echo "3. Current .env (if sourced):"
echo $PROJECT_ID

echo "4. Terraform State (if initialized):"
cd terraform/gcp-gitea
terraform show | grep project_id | head -5
```

**If any of these differ, you have misaligned contexts!**

### Method 1: Using Make Targets (Recommended)

The Makefile provides safe environment switching:

```bash
# Show current environment
make show-environment

# Verify project context
make verify-project

# Switch environment (if make target exists)
make switch-env ENV=staging
```

**What `make show-environment` displays:**
```
Current Environment Configuration
==================================
GCloud Active Project:   dcg-gitea-stage
Makefile PROJECT_ID:     dcg-gitea-stage
Makefile ENVIRONMENT:    staging

Terraform State:
  State file exists: YES
  terraform.tfvars: Not found (GOOD)
  terraform.tfvars.staging: EXISTS

Safety Scripts:
  ✓ terraform-project-validator.sh
  ✓ pre-destroy-validator.sh
  ✓ gcp-destroy.sh

Documentation: docs/SAFE_OPERATIONS_GUIDE.md
```

### Method 2: Manual Switching with .env Files

**Step-by-step procedure:**

```bash
# 1. Determine target environment
TARGET_ENV="staging"  # or "dev"

# 2. Source the environment file
cd /home/notme/Desktop/code/DCG/gitea
source .env.${TARGET_ENV}

# Verify environment variables are set
echo "Switching to: $PROJECT_ID ($ENVIRONMENT)"
echo "Will use: $VAR_FILE"

# 3. Set GCloud project
gcloud config set project $PROJECT_ID

# Verify
gcloud config get-value project  # Should match $PROJECT_ID

# 4. Navigate to Terraform directory
cd terraform/gcp-gitea

# 5. Reconfigure Terraform backend
terraform init -reconfigure \
  -backend-config="bucket=${PROJECT_ID}-gitea-tfstate-$(terraform output -raw state_bucket_suffix 2>/dev/null || echo 'xxxxx')" \
  -backend-config="prefix=terraform/state"

# Note: You may need to provide exact bucket name
# Get it from: gsutil ls | grep tfstate

# 6. Verify new context
terraform show | grep project_id | head -5

# Should show resources from $PROJECT_ID

# 7. Test with a plan (using explicit -var-file)
terraform plan -var-file=$VAR_FILE

# Review output to confirm correct environment
```

### Method 3: Using Terraform Workspaces (Alternative)

**Note**: This project doesn't currently use Terraform workspaces, but they can be added:

```bash
# Initialize workspaces for environments
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Switch workspaces
terraform workspace select staging

# Verify
terraform workspace show  # staging

# Still need explicit -var-file
terraform plan -var-file=terraform.tfvars.staging
```

**Pros:**
- Built-in Terraform feature
- Clear separation of state
- Easy to see current workspace

**Cons:**
- Doesn't change gcloud context
- Doesn't automatically select correct .tfvars file
- Still need manual verification

### Verification Steps After Switching

**Mandatory verification checklist:**

```bash
# Checklist for environment verification
cat > /tmp/env_verify.sh << 'EOF'
#!/bin/bash
set -e

EXPECTED_PROJECT="${1:-}"
if [ -z "$EXPECTED_PROJECT" ]; then
    echo "Usage: $0 <expected-project-id>"
    exit 1
fi

echo "Verifying environment: $EXPECTED_PROJECT"
echo "======================================="

# Check 1: GCloud
GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ "$GCLOUD_PROJECT" = "$EXPECTED_PROJECT" ]; then
    echo "✓ GCloud: $GCLOUD_PROJECT"
else
    echo "✗ GCloud: $GCLOUD_PROJECT (expected: $EXPECTED_PROJECT)"
    exit 1
fi

# Check 2: Backend
cd terraform/gcp-gitea
BACKEND_BUCKET=$(grep bucket backend.tf | awk -F'"' '{print $2}')
if echo "$BACKEND_BUCKET" | grep -q "$EXPECTED_PROJECT"; then
    echo "✓ Backend: $BACKEND_BUCKET"
else
    echo "✗ Backend: $BACKEND_BUCKET (doesn't contain: $EXPECTED_PROJECT)"
    exit 1
fi

# Check 3: State
STATE_PROJECT=$(terraform show 2>/dev/null | grep 'project.*=' | head -1 | awk -F'"' '{print $2}')
if [ "$STATE_PROJECT" = "$EXPECTED_PROJECT" ]; then
    echo "✓ State: $STATE_PROJECT"
else
    echo "✗ State: $STATE_PROJECT (expected: $EXPECTED_PROJECT)"
    exit 1
fi

echo ""
echo "✓ All checks passed! Environment is: $EXPECTED_PROJECT"
EOF

chmod +x /tmp/env_verify.sh

# Run verification
/tmp/env_verify.sh dcg-gitea-stage
```

**If ANY check fails, do NOT proceed with infrastructure operations!**

---

## Variable File Naming Conventions

### File Naming Standard

```
terraform.tfvars.{environment}
                 └─ Environment identifier (dev/staging/prod)
```

**Allowed names:**
- `terraform.tfvars.dev` - Development environment
- `terraform.tfvars.staging` - Staging environment
- `terraform.tfvars.prod` - Production environment (reference only)
- `terraform.tfvars.example` - Template/documentation

**Forbidden names:**
- `terraform.tfvars` - Too ambiguous, auto-loaded by Terraform
- `terraform.auto.tfvars` - Auto-loaded by Terraform
- `dev.tfvars` - Doesn't follow convention
- `staging-vars.tfvars` - Doesn't follow convention

### MUST Use Explicit -var-file Parameter

**Critical Rule: ALWAYS specify -var-file explicitly**

**❌ WRONG - Relies on Auto-Loading:**
```bash
terraform plan                     # Which environment?
terraform apply                    # Dangerous!
terraform destroy                  # Catastrophic risk!
```

**✅ CORRECT - Explicit Parameter:**
```bash
terraform plan -var-file=terraform.tfvars.staging      # Clear
terraform apply -var-file=terraform.tfvars.staging     # Obvious
terraform destroy -var-file=terraform.tfvars.staging   # Safe
```

### What to Include in .tfvars Files

**Required variables (must be set):**
```hcl
project_id = "dcg-gitea-stage"      # GCP project ID
environment = "staging"              # Environment name
region = "us-central1"               # GCP region
zone = "us-central1-a"               # GCP zone
```

**Infrastructure configuration:**
```hcl
machine_type = "e2-standard-4"       # Compute instance type
boot_disk_size = 100                 # Boot disk GB
data_disk_size = 200                 # Data disk GB
subnet_cidr = "10.0.1.0/24"         # Network CIDR
```

**Security settings:**
```hcl
enable_os_login = true               # OS Login for SSH
enable_kms = true                    # Encryption keys
enable_secret_manager = true         # Secrets management
enable_cloud_armor = true            # WAF protection
```

**Application settings:**
```hcl
gitea_domain = "git-stage.dcg.cui-secure.us"
gitea_admin_username = "admin"
gitea_admin_email = "nmartin@dcg.cui-secure.us"
gitea_disable_registration = true
```

**Retention policies:**
```hcl
evidence_retention_days = 2555       # 7 years for CMMC
backup_retention_days = 7            # Short for non-prod
logs_retention_days = 30             # Minimal for staging
```

### What to EXCLUDE from .tfvars Files

**Never include in .tfvars:**
- Passwords or secrets (use Secret Manager)
- API keys or tokens (use Secret Manager)
- Private SSH keys (use OS Login or Secret Manager)
- Database credentials (auto-generated, stored in Secret Manager)
- TLS private keys (use Certificate Manager or Secret Manager)

**Secret handling pattern:**
```hcl
# In terraform.tfvars.staging
gitea_admin_password = null          # Will be auto-generated
postgres_password = null             # Will be auto-generated

# Secrets are:
# 1. Generated by Terraform (random_password resource)
# 2. Stored in GCP Secret Manager
# 3. Never written to .tfvars files
# 4. Retrieved at runtime by application
```

---

## Common Workflows

### Workflow 1: Deploy to Staging (Step-by-Step)

**Prerequisites:**
- Staging project exists (dcg-gitea-stage)
- Bootstrap resources created (state bucket, KMS keys)
- DNS configured for staging domain

**Procedure:**

```bash
# Step 1: Switch to staging environment
cd /home/notme/Desktop/code/DCG/gitea
source .env.staging

echo "Switching to: $PROJECT_ID"

# Step 2: Set GCloud project
gcloud config set project $PROJECT_ID
gcloud config get-value project  # Verify

# Step 3: Navigate to Terraform directory
cd terraform/gcp-gitea

# Step 4: Initialize Terraform with staging backend
# Get exact bucket name first
gsutil ls | grep tfstate | grep $PROJECT_ID
# Example output: gs://dcg-gitea-stage-gitea-tfstate-e1fd2206/

terraform init -reconfigure \
  -backend-config="bucket=dcg-gitea-stage-gitea-tfstate-e1fd2206" \
  -backend-config="prefix=terraform/state"

# Step 5: Validate configuration
terraform validate

# Step 6: Format check
terraform fmt -check

# Step 7: Generate plan with explicit var-file
terraform plan \
  -var-file=terraform.tfvars.staging \
  -out=tfplan-staging

# Step 8: Review plan carefully
terraform show tfplan-staging | less

# Verify:
# - All resource names contain "dcg-gitea-stage"
# - Project ID is dcg-gitea-stage everywhere
# - No resources from other environments

# Step 9: Run validation script
cd /home/notme/Desktop/code/DCG/gitea
./scripts/terraform-project-validator.sh \
  --operation=plan \
  --project=dcg-gitea-stage \
  --terraform-dir=terraform/gcp-gitea

# Step 10: Apply the plan
cd terraform/gcp-gitea
terraform apply tfplan-staging

# Step 11: Verify deployment
terraform output

# Step 12: Test application
EXTERNAL_IP=$(terraform output -raw gitea_external_ip)
curl -I https://$EXTERNAL_IP  # Should return HTTP 200 or redirect

# Step 13: Collect evidence
cd /home/notme/Desktop/code/DCG/gitea
make evidence-collect ENVIRONMENT=staging
make evidence-upload ENVIRONMENT=staging
```

### Workflow 2: Deploy to Production (With Extra Validation)

**Note:** cui-gitea-prod is decommissioned. This workflow is for reference or future production environment.

**Prerequisites:**
- Change request approved
- Peer review completed
- Recent backup verified
- Maintenance window scheduled
- Rollback plan documented

**Procedure:**

```bash
# Step 1: Pre-deployment verification
cd /home/notme/Desktop/code/DCG/gitea

# Verify peer review approval
echo "Change Request: CR-YYYY-XXXX"
echo "Approved By: [Name]"
echo "Approval Date: [Date]"
read -p "Confirm CR approval (yes/no): " approval
[ "$approval" != "yes" ] && echo "Aborted" && exit 1

# Step 2: Switch to production environment
source .env.prod

echo "SWITCHING TO PRODUCTION: $PROJECT_ID"
echo "Are you absolutely certain?"
read -p "Type the full project ID to confirm: " confirm
[ "$confirm" != "$PROJECT_ID" ] && echo "Aborted" && exit 1

# Step 3: Set GCloud project
gcloud config set project $PROJECT_ID
gcloud config get-value project

# Step 4: Verify backup exists
gsutil ls gs://${PROJECT_ID}-gitea-backups/ | tail -5
echo "Last backup age should be < 24 hours"
read -p "Backup verified? (yes/no): " backup_ok
[ "$backup_ok" != "yes" ] && echo "Aborted" && exit 1

# Step 5: Navigate and initialize
cd terraform/gcp-gitea

BUCKET=$(gsutil ls | grep tfstate | grep $PROJECT_ID | head -1 | sed 's|gs://||' | sed 's|/||')
echo "State bucket: $BUCKET"

terraform init -reconfigure \
  -backend-config="bucket=$BUCKET" \
  -backend-config="prefix=terraform/state"

# Step 6: Security scan
cd /home/notme/Desktop/code/DCG/gitea
make security-scan

# Review security findings
cat /tmp/checkov-results.json | jq '.summary'
cat /tmp/tfsec-results.json | jq '.results | length'

# Step 7: Generate plan
cd terraform/gcp-gitea
terraform plan \
  -var-file=terraform.tfvars.prod \
  -out=tfplan-prod

# Step 8: Comprehensive validation
cd /home/notme/Desktop/code/DCG/gitea
./scripts/terraform-project-validator.sh \
  --operation=plan \
  --project=$PROJECT_ID \
  --terraform-dir=terraform/gcp-gitea

# Step 9: Peer review of plan
cd terraform/gcp-gitea
terraform show tfplan-prod > /tmp/prod-deployment-plan.txt
echo "Plan saved to: /tmp/prod-deployment-plan.txt"
echo "Send to peer reviewer for approval"
read -p "Peer review approved? (yes/no): " peer_ok
[ "$peer_ok" != "yes" ] && echo "Aborted" && exit 1

# Step 10: Final confirmation
echo "═══════════════════════════════════════"
echo "  PRODUCTION DEPLOYMENT - FINAL CHECK  "
echo "═══════════════════════════════════════"
echo "Project: $PROJECT_ID"
echo "Change Request: [CR number]"
echo "Peer Reviewer: [Name]"
echo "Backup Verified: Yes"
echo "Security Scan: Passed"
echo "Maintenance Window: [Time]"
echo "═══════════════════════════════════════"
read -p "Type 'DEPLOY' to proceed: " final
[ "$final" != "DEPLOY" ] && echo "Aborted" && exit 1

# Step 11: Execute deployment
terraform apply tfplan-prod 2>&1 | tee /tmp/prod-deployment-$(date +%Y%m%d_%H%M%S).log

# Step 12: Post-deployment validation
terraform output

# Step 13: Application health check
EXTERNAL_IP=$(terraform output -raw gitea_external_ip)
curl -I https://$EXTERNAL_IP
# Verify HTTP 200 response

# Step 14: Collect deployment evidence
cd /home/notme/Desktop/code/DCG/gitea
make evidence-collect ENVIRONMENT=prod
make evidence-upload ENVIRONMENT=prod

# Step 15: Update documentation
echo "Deployment completed: $(date)" >> terraform/gcp-gitea/DEPLOYMENT_PROGRESS.md
```

### Workflow 3: Switch Environments for Testing

**Scenario:** Working on staging, need to check development.

```bash
# Currently in staging
echo "Current environment: $PROJECT_ID"  # dcg-gitea-stage

# Step 1: Clean workspace (optional but recommended)
cd /home/notme/Desktop/code/DCG/gitea/terraform/gcp-gitea
rm -f tfplan* destroy.tfplan

# Step 2: Switch environment
cd /home/notme/Desktop/code/DCG/gitea
source .env.dev

echo "Switched to: $PROJECT_ID"  # dcg-gitea-dev

# Step 3: Update GCloud
gcloud config set project $PROJECT_ID
gcloud config get-value project

# Step 4: Reinitialize Terraform
cd terraform/gcp-gitea

terraform init -reconfigure \
  -backend-config="bucket=${PROJECT_ID}-gitea-tfstate-xxxxx" \
  -backend-config="prefix=terraform/state"

# Step 5: Verify new context
terraform show | grep project_id | head -5
# Should all show dcg-gitea-dev

# Step 6: Safe to operate in new environment
terraform plan -var-file=terraform.tfvars.dev
```

### Workflow 4: Validate Current Environment

**Quick validation before any operation:**

```bash
# Method 1: Using Makefile
cd /home/notme/Desktop/code/DCG/gitea
make show-environment

# Method 2: Using validation script
./scripts/terraform-project-validator.sh \
  --operation=validate \
  --project=$(gcloud config get-value project) \
  --terraform-dir=terraform/gcp-gitea

# Method 3: Manual verification
echo "GCloud: $(gcloud config get-value project)"
echo "Backend: $(grep bucket terraform/gcp-gitea/backend.tf | awk -F'"' '{print $2}')"
cd terraform/gcp-gitea
echo "State: $(terraform show | grep project_id | head -1 | awk -F'"' '{print $2}')"
```

---

## Troubleshooting

### Problem 1: "Wrong Project!" - GCloud Mismatch

**Symptoms:**
```bash
terraform plan -var-file=terraform.tfvars.staging
# Error: Error creating instance: googleapi: Error 403: Project dcg-gitea-stage is not found
```

**Cause:** GCloud is set to different project than var-file specifies.

**Diagnosis:**
```bash
# Check gcloud
gcloud config get-value project
# Output: cui-gitea-prod

# Check var-file
grep project_id terraform.tfvars.staging
# Output: project_id = "dcg-gitea-stage"

# MISMATCH!
```

**Solution:**
```bash
# Set gcloud to match var-file
gcloud config set project dcg-gitea-stage
gcloud config get-value project  # Verify

# Retry operation
terraform plan -var-file=terraform.tfvars.staging
```

### Problem 2: terraform.tfvars Exists Warning

**Symptoms:**
```bash
terraform plan -var-file=terraform.tfvars.staging
# Warning: Values from terraform.tfvars will also be used
```

**Cause:** A `terraform.tfvars` file exists and is being auto-loaded in addition to your explicit var-file.

**Diagnosis:**
```bash
cd terraform/gcp-gitea
ls -la terraform.tfvars
# Output: -rw-rw-r-- 1 user user 6347 Oct 09 15:22 terraform.tfvars

grep project_id terraform.tfvars
# Output: project_id = "dcg-gitea-stage"
```

**Risk:** If `terraform.tfvars` contains different values than your explicit var-file, variable precedence rules apply and results may be unexpected.

**Solution:**
```bash
# Option 1: Delete the ambiguous file
cd terraform/gcp-gitea
rm terraform.tfvars

# Option 2: Rename it to environment-specific
mv terraform.tfvars terraform.tfvars.backup

# Verify it's gone
ls terraform.tfvars
# Output: ls: cannot access 'terraform.tfvars': No such file or directory

# Retry operation
terraform plan -var-file=terraform.tfvars.staging  # No warning
```

### Problem 3: Multiple .tfvars Files Confusion

**Symptoms:**
```bash
ls terraform.tfvars*
# terraform.tfvars
# terraform.tfvars.dev
# terraform.tfvars.staging
# terraform.tfvars.prod

# Which one is being used?
```

**Diagnosis:**
```bash
# Terraform auto-loads (in order):
# 1. terraform.tfvars
# 2. terraform.tfvars.json
# 3. *.auto.tfvars (alphabetically)
# 4. Then your explicit -var-file

# Check what will be loaded automatically:
cd terraform/gcp-gitea
ls terraform.tfvars terraform.tfvars.json *.auto.tfvars 2>/dev/null
```

**Solution:**
```bash
# Remove all auto-loaded files
cd terraform/gcp-gitea
rm -f terraform.tfvars terraform.tfvars.json *.auto.tfvars

# Keep only environment-specific files
ls terraform.tfvars.*
# terraform.tfvars.dev
# terraform.tfvars.staging
# terraform.tfvars.prod
# terraform.tfvars.example

# Always use explicit -var-file
terraform plan -var-file=terraform.tfvars.staging
```

### Problem 4: GCloud Project Mismatch with Backend

**Symptoms:**
```bash
terraform plan -var-file=terraform.tfvars.staging
# Error: Error reading state: blob gs://cui-gitea-prod-gitea-tfstate-*/terraform/state/default.tfstate: storage: object doesn't exist
```

**Cause:** Terraform backend is configured for different project than gcloud/var-file.

**Diagnosis:**
```bash
# Check gcloud
gcloud config get-value project
# Output: dcg-gitea-stage

# Check backend
grep bucket terraform/gcp-gitea/backend.tf
# Output: bucket = "cui-gitea-prod-gitea-tfstate-f5f2e413"

# MISMATCH! Backend points to cui-gitea-prod but gcloud is dcg-gitea-stage
```

**Solution:**
```bash
# Reconfigure backend to match target environment
cd terraform/gcp-gitea

# Get correct bucket name
TARGET_PROJECT="dcg-gitea-stage"
BUCKET=$(gsutil ls | grep tfstate | grep $TARGET_PROJECT | head -1 | sed 's|gs://||' | sed 's|/||')
echo "Target bucket: $BUCKET"

# Reinitialize with correct backend
terraform init -reconfigure \
  -backend-config="bucket=$BUCKET" \
  -backend-config="prefix=terraform/state"

# Verify state matches project
terraform show | grep project_id | head -5
# Should all show dcg-gitea-stage
```

### Problem 5: State Shows Wrong Environment Resources

**Symptoms:**
```bash
terraform state list
# google_compute_instance.gitea-cui-gitea-prod-vm
# google_compute_network.cui-gitea-prod-network
# ...

# But I'm trying to work on staging!
```

**Cause:** Terraform backend is initialized to wrong environment's state.

**Diagnosis:**
```bash
# Check backend
grep bucket terraform/gcp-gitea/backend.tf
# Output: bucket = "cui-gitea-prod-gitea-tfstate-f5f2e413"

# This is production state bucket, not staging!
```

**Solution:**
```bash
# Do NOT try to "fix" state with terraform state rm
# Instead, reinitialize to correct backend

cd terraform/gcp-gitea

# Backup current state just in case
terraform state pull > /tmp/wrong-state-backup.tfstate

# Reinitialize to staging backend
terraform init -reconfigure \
  -backend-config="bucket=dcg-gitea-stage-gitea-tfstate-e1fd2206" \
  -backend-config="prefix=terraform/state"

# Verify resources now match staging
terraform state list
# google_compute_instance.gitea-dcg-gitea-stage-vm
# google_compute_network.dcg-gitea-stage-network
# ...

# Now you're operating on staging state
```

### Problem 6: "Backend Configuration Changed"

**Symptoms:**
```bash
terraform plan -var-file=terraform.tfvars.staging
# Error: Backend configuration changed
# A backend configuration change was detected. Terraform needs to reinitialize.
```

**Cause:** backend.tf was modified or you switched environments.

**Solution:**
```bash
# Simply reinitialize
terraform init -reconfigure

# If prompted to migrate state, be careful!
# Only migrate if you're intentionally moving state between backends
# Otherwise answer "no" and investigate

# After reconfigure, verify correct environment
terraform show | grep project_id | head -5
```

---

## Best Practices

### 1. Always Verify Before Destructive Operations

**Mandatory validation before:**
- `terraform destroy`
- `terraform apply` (if plan shows deletions)
- Any gcloud delete command
- Any manual resource deletion in GCP console

**Validation checklist:**
```bash
# Run validation script
cd /home/notme/Desktop/code/DCG/gitea
./scripts/terraform-project-validator.sh \
  --operation=destroy \
  --project=$(gcloud config get-value project) \
  --terraform-dir=terraform/gcp-gitea

# Or use Makefile
make verify-project
make show-environment
```

### 2. Use Make Targets Instead of Raw Commands

**Prefer:**
```bash
make validate                        # Validates all configs
make validate-project                # Validates environment context
make show-environment                # Shows current state
make safe-destroy                    # Destruction with validation
```

**Over:**
```bash
terraform validate                   # No context validation
terraform destroy                    # No safety checks
```

**Rationale:**
- Make targets include safety validations
- Consistent across team members
- Self-documenting operations
- Can't forget validation steps

### 3. Keep .env Files Out of Git

**.gitignore should include:**
```
.env.local
.env.*.local
terraform.tfvars
*.tfstate
*.tfstate.backup
.terraform/
```

**Exception:** Environment-specific files that are safe for team:
```
.env.dev                    # Safe - no secrets
.env.staging                # Safe - no secrets
.env.prod                   # Safe - no secrets
.env.example                # Template
```

**Never commit:**
- Files with actual passwords or secrets
- Local overrides (.env.local)
- Working copies (terraform.tfvars)

### 4. Regular Environment Verification

**Daily practice:**
```bash
# At start of work session
cd /home/notme/Desktop/code/DCG/gitea
make show-environment

# Before any Terraform operation
make verify-project

# After switching environments
source .env.staging
make verify-project
```

**Weekly practice:**
```bash
# Verify all environment files are in sync
for env in dev staging prod; do
    echo "=== $env ==="
    grep project_id terraform/gcp-gitea/terraform.tfvars.$env
    grep PROJECT_ID .env.$env
done
```

### 5. Document Environment Changes

**Maintain environment change log:**
```bash
# File: terraform/gcp-gitea/ENVIRONMENT_CHANGELOG.md

## 2025-10-13
- Decommissioned cui-gitea-prod
- Updated .env.prod with DECOMMISSIONED notice
- Set terraform.tfvars.prod to read-only reference

## 2025-10-09
- Created dcg-gitea-stage environment
- Deployed staging infrastructure
- Configured git-stage.dcg.cui-secure.us domain

## 2025-10-07
- Initial cui-gitea-prod deployment
- Configured gitea.cui-secure.us domain
```

### 6. Use Descriptive Git Commit Messages

**Environment-specific commits should mention environment:**
```bash
git commit -m "feat(staging): Deploy Gitea to dcg-gitea-stage

- Created terraform.tfvars.staging
- Configured e2-standard-4 instance
- Set 7-day backup retention
- Deployed to git-stage.dcg.cui-secure.us"

git commit -m "fix(prod): Correct KMS keyring location in terraform.tfvars.prod"

git commit -m "docs: Add environment switching procedures to ENVIRONMENT_MANAGEMENT.md"
```

### 7. Peer Review for Production Changes

**Always required:**
- Production deployments
- Production configuration changes
- Production destruction operations

**Peer review process:**
```bash
# 1. Create plan
terraform plan -var-file=terraform.tfvars.prod -out=tfplan-prod

# 2. Generate review file
terraform show tfplan-prod > /tmp/prod-change-review.txt

# 3. Share with peer
# Email or Slack: "Please review production change: /tmp/prod-change-review.txt"

# 4. Wait for approval
# Peer should check:
# - Correct environment
# - Expected changes only
# - No accidental deletions
# - Compliance with change request

# 5. After approval, apply
terraform apply tfplan-prod
```

### 8. Test in Lower Environments First

**Deployment order:**
1. Development (dcg-gitea-dev) - Test changes
2. Staging (dcg-gitea-stage) - Integration testing
3. Production (future) - After validation

**Never:**
- Deploy directly to production without staging validation
- Test destructive operations in production
- Experiment with new features in production

---

## Incident Prevention

### Lessons from dcg-gitea-stage Incident (October 13, 2025)

**Incident Summary:**
- **Date**: 2025-10-13
- **Operator**: Claude AI assisting human operator
- **Intent**: Destroy resources in cui-gitea-prod (decommissioned production)
- **Actual**: Destroyed resources in dcg-gitea-stage (active staging)
- **Impact**: 86 resources destroyed, ~4 hours recovery time
- **Cause**: Terraform backend misalignment

**What went wrong:**
1. backend.tf was hardcoded to dcg-gitea-stage bucket
2. gcloud config showed cui-gitea-prod
3. terraform.tfvars.prod specified cui-gitea-prod
4. Operator verified gcloud and var-file matched
5. Did NOT verify Terraform backend matched
6. Terraform used dcg-gitea-stage backend → destroyed staging resources

**Prevention measures implemented:**

#### 1. Enhanced Validation Scripts

**terraform-project-validator.sh:**
```bash
# Checks all three contexts:
# 1. GCloud project
# 2. Terraform backend bucket
# 3. Terraform state contents
# 4. Variable file project_id

# Fails if ANY mismatch detected
```

**pre-destroy-validator.sh:**
```bash
# Pre-destruction validation:
# 1. Verifies intended project
# 2. Generates destroy plan
# 3. Searches plan for wrong project names
# 4. Counts resources to destroy
# 5. Requires explicit confirmation

# MUST pass before destruction allowed
```

#### 2. Updated Make Targets

**make show-environment:**
- Shows all three contexts
- Highlights mismatches
- Displays safety script status

**make verify-project:**
- Validates gcloud matches Makefile PROJECT_ID
- Fails with clear error if mismatch

**make safe-destroy:**
- Runs all validation scripts
- Requires double confirmation
- Generates evidence logs
- Creates audit trail

#### 3. Documentation

**This document (ENVIRONMENT_MANAGEMENT.md):**
- Comprehensive environment switching procedures
- Clear explanation of three contexts
- Common pitfalls and solutions

**SAFE_OPERATIONS_GUIDE.md:**
- 10-point pre-flight checklist
- Destruction safety protocol
- Emergency rollback procedures

### Red Flags to Watch For

**Warning signs of potential environment mismatch:**

1. **Resource names don't match expected project**
   ```bash
   terraform plan | head -20
   # If you see: cui-gitea-prod-* but expect dcg-gitea-stage-*
   # STOP! Wrong environment!
   ```

2. **Unexpected resource count**
   ```bash
   terraform state list | wc -l
   # Output: 86
   # Expected for staging: 50
   # STOP! This might be wrong environment!
   ```

3. **Backend bucket name doesn't match project**
   ```bash
   grep bucket backend.tf
   # bucket = "cui-gitea-prod-..."
   # But working on staging?
   # STOP! Backend mismatch!
   ```

4. **State shows different project than expected**
   ```bash
   terraform show | grep project_id | head -1
   # project_id = "cui-gitea-prod"
   # But expecting dcg-gitea-stage?
   # STOP! Wrong state!
   ```

5. **Multiple confirmations needed**
   - If you find yourself thinking "this doesn't look right"
   - If resource names are unexpected
   - If counts seem off
   - **STOP AND INVESTIGATE!**

### Pre-Flight Checklist Reference

**Use this before ANY Terraform operation:**

```
╔══════════════════════════════════════════════════════════════╗
║            ENVIRONMENT VERIFICATION CHECKLIST                ║
╠══════════════════════════════════════════════════════════════╣
║ Operation: _________________________________________         ║
║ Target Environment: _________________________________        ║
║ Date: _______________ Operator: _____________________        ║
║                                                              ║
║ CONTEXT VERIFICATION                                         ║
║ [ ] 1. GCloud project matches target                        ║
║        Command: gcloud config get-value project             ║
║        Expected: ____________________________               ║
║                                                              ║
║ [ ] 2. Terraform backend matches target                     ║
║        Command: grep bucket terraform/gcp-gitea/backend.tf  ║
║        Expected: Contains ____________________________      ║
║                                                              ║
║ [ ] 3. Terraform state shows target resources               ║
║        Command: terraform show | grep project_id | head -5  ║
║        Expected: All show ____________________________      ║
║                                                              ║
║ [ ] 4. Using explicit -var-file parameter                   ║
║        Command: terraform ... -var-file=terraform.tfvars.__ ║
║        Var-file: ____________________________               ║
║                                                              ║
║ [ ] 5. Validation script passed                             ║
║        Command: ./scripts/terraform-project-validator.sh    ║
║        Result: PASSED / FAILED                              ║
║                                                              ║
║ SAFETY CHECKS                                                ║
║ [ ] 6. make show-environment executed                       ║
║ [ ] 7. make verify-project passed                           ║
║ [ ] 8. Resource names match expected project                ║
║ [ ] 9. Resource count is within expected range              ║
║ [ ] 10. Peer review completed (if required)                 ║
║                                                              ║
║ If ALL boxes checked: SAFE TO PROCEED                       ║
║ If ANY box unchecked: STOP AND INVESTIGATE                  ║
╚══════════════════════════════════════════════════════════════╝
```

### Safety Validation Tools

**Available scripts:**

```bash
# Comprehensive validation
/home/notme/Desktop/code/DCG/gitea/scripts/terraform-project-validator.sh
# Validates all three contexts, provides clear pass/fail

# Pre-destruction validation
/home/notme/Desktop/code/DCG/gitea/scripts/pre-destroy-validator.sh
# Checks destroy plan for wrong project, unexpected resources

# Safe destruction wrapper
/home/notme/Desktop/code/DCG/gitea/scripts/gcp-destroy.sh
# Automated validation + destruction with evidence collection
```

**Make targets:**

```bash
make show-environment        # Display current configuration
make verify-project          # Verify GCloud matches Makefile
make validate-project        # Run full validation script
make validate-destroy        # Run pre-destroy validation
make safe-destroy            # Safe destruction with all checks
```

---

## Quick Reference Card

### Environment Summary

| Environment | Project ID | Status | Var-File |
|-------------|-----------|--------|----------|
| Development | dcg-gitea-dev | Planned | terraform.tfvars.dev |
| Staging | dcg-gitea-stage | Active | terraform.tfvars.staging |
| Production | cui-gitea-prod | Decommissioned | terraform.tfvars.prod (reference) |

### Essential Commands

```bash
# Show current environment
make show-environment

# Verify project context
make verify-project

# Switch to staging
source .env.staging
gcloud config set project $PROJECT_ID
cd terraform/gcp-gitea
terraform init -reconfigure -backend-config="bucket=dcg-gitea-stage-gitea-tfstate-e1fd2206"

# Validate environment
./scripts/terraform-project-validator.sh --project=dcg-gitea-stage

# Safe operations
terraform plan -var-file=terraform.tfvars.staging
terraform apply -var-file=terraform.tfvars.staging
```

### Three Contexts Checklist

```
Context 1: GCloud  → gcloud config get-value project
Context 2: Backend → grep bucket backend.tf
Context 3: State   → terraform show | grep project_id

All three MUST match target environment!
```

### When in Doubt

```bash
# Stop and validate
make show-environment
make verify-project

# Run validation script
./scripts/terraform-project-validator.sh

# If ANY check fails: STOP and investigate
# If unsure: Ask for peer review
# If emergency: See SAFE_OPERATIONS_GUIDE.md
```

---

## Related Documentation

- **SAFE_OPERATIONS_GUIDE.md** - Safety procedures for Terraform operations
- **GCP_OPERATIONS_RUNBOOK.md** - Day-to-day operational procedures
- **GCP_DISASTER_RECOVERY.md** - Recovery procedures for incidents
- **CUI_GITEA_DECOMMISSION_PLAN.md** - Production decommissioning procedures
- **AGENTS.md** - Repository guidelines and conventions

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-13 | Claude AI | Initial version based on dcg-gitea-stage incident |

---

## Appendix A: Variable Precedence Deep Dive

### Terraform Variable Loading Order

Terraform loads variables in this order (later overrides earlier):

```
1. Default values in *.tf files
2. TF_VAR_* environment variables
3. terraform.tfvars (auto-loaded if exists)
4. terraform.tfvars.json (auto-loaded if exists)
5. *.auto.tfvars (auto-loaded, alphabetically)
6. -var-file=<file> (explicit parameters, in order specified)
7. -var <key>=<value> (explicit flags, in order specified)
```

### Example: Multiple Sources

```bash
# variables.tf
variable "project_id" {
  default = "default-project"     # Priority 1 (lowest)
}

# Environment variable
export TF_VAR_project_id="env-project"   # Priority 2

# terraform.tfvars (if exists)
project_id = "auto-project"       # Priority 3

# Command line
terraform plan \
  -var-file=terraform.tfvars.staging \    # Priority 6: project_id = "dcg-gitea-stage"
  -var="project_id=cli-project"           # Priority 7: (highest - WINS)

# Result: project_id = "cli-project"
```

### Why Explicit -var-file is Best

**Advantages:**
1. Clear in command what's being used
2. Visible in shell history
3. Self-documenting
4. No ambiguity
5. Team members can see intent

**Disadvantages of auto-loading:**
1. Hidden behavior
2. Easy to forget which file exists
3. Silent failures
4. Hard to debug
5. Precedence confusion

---

## Appendix B: Backend Configuration Patterns

### Static Backend (Current Approach)

**backend.tf:**
```hcl
terraform {
  backend "gcs" {
    bucket = "dcg-gitea-stage-gitea-tfstate-e1fd2206"
    prefix = "terraform/state"
  }
}
```

**Pros:**
- Simple
- Version controlled
- Easy to understand

**Cons:**
- Must be manually updated when switching environments
- Can get out of sync
- Requires terraform init -reconfigure after changes

### Dynamic Backend (Alternative Approach)

**backend.tf:**
```hcl
terraform {
  backend "gcs" {
    # bucket configured via -backend-config at init
    # prefix configured via -backend-config at init
  }
}
```

**Initialize with:**
```bash
terraform init \
  -backend-config="bucket=${PROJECT_ID}-gitea-tfstate-xxxxx" \
  -backend-config="prefix=terraform/state"
```

**Pros:**
- Can specify backend at initialization time
- Easier to switch environments
- No backend.tf edits needed

**Cons:**
- More complex initialization
- Must remember correct bucket name
- Not visible in version control

### Workspace-Based Approach (Future Consideration)

```bash
# Create workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Switch workspace
terraform workspace select staging

# Plan with workspace
terraform plan -var-file=terraform.tfvars.staging
```

**Pros:**
- Built-in Terraform feature
- Separate states automatically
- Clear current workspace

**Cons:**
- Still need separate var-files
- Doesn't change gcloud context
- Requires team training

---

**END OF ENVIRONMENT MANAGEMENT GUIDE**

*For questions or improvements to this guide, create a pull request or contact the Platform Team.*

*Remember: When in doubt, validate. Better to spend 2 minutes verifying than 4 hours recovering.*
