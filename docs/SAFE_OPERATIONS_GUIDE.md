# Safe Operations Guide
## Terraform Project Selection & Destruction Safety Procedures

**Document Version**: 1.0
**Created**: 2025-10-13
**Last Updated**: 2025-10-13
**Status**: ACTIVE
**Compliance**: CMMC 2.0 Level 2, NIST SP 800-171 Rev. 2

---

## Purpose

This guide establishes mandatory safety procedures for Terraform operations across multiple GCP projects to prevent accidental resource destruction in the wrong environment. These procedures were developed in response to incident INC-2025-1013-001 (dcg-gitea-stage accidental destruction).

**Key Principle**: *"Validate then Execute"* - Always verify context before any destructive operation.

---

## Table of Contents

1. [Pre-Flight Checklist](#pre-flight-checklist)
2. [Environment Selection Protocol](#environment-selection-protocol)
3. [Terraform Variable Hierarchy](#terraform-variable-hierarchy)
4. [Project Verification Commands](#project-verification-commands)
5. [Destruction Safety Protocol](#destruction-safety-protocol)
6. [Common Pitfalls](#common-pitfalls)
7. [Emergency Rollback](#emergency-rollback)
8. [Approval Workflow](#approval-workflow)
9. [Incident Response](#incident-response)
10. [Quick Reference](#quick-reference)

---

## Pre-Flight Checklist

### Mandatory 10-Point Verification

**Use this checklist before ANY Terraform operation that modifies or destroys resources.**

```
[ ] 1. Current working directory verified
       Command: pwd
       Expected: /home/notme/Desktop/code/DCG/gitea/terraform/gcp-gitea

[ ] 2. GCloud active project verified
       Command: gcloud config get-value project
       Expected: Matches intended target (cui-gitea-prod, dcg-gitea-stage, etc.)

[ ] 3. Terraform backend bucket verified
       Command: grep bucket backend.tf
       Expected: Bucket name contains correct project ID

[ ] 4. Variable file explicitly specified
       Command: ls -l terraform.tfvars.*
       Action: Always use -var-file=terraform.tfvars.<env>, NEVER rely on auto-loading

[ ] 5. Terraform state contains correct project
       Command: terraform show | grep project_id | head -5
       Expected: All resources show intended project

[ ] 6. Resource names match intended project
       Command: terraform state list | head -10
       Expected: All resources prefixed with correct project name

[ ] 7. Destroy plan generated and reviewed
       Command: terraform plan -destroy -var-file=terraform.tfvars.<env> -out=destroy.tfplan
       Action: Manual review of ALL resources to be destroyed

[ ] 8. Wrong project name NOT in plan
       Command: terraform show destroy.tfplan | grep -c "<wrong-project-id>"
       Expected: 0 matches

[ ] 9. Resource count validated
       Expected: Within 10% of documented resource count for environment

[ ] 10. Double confirmation obtained
        Action: Type intended project ID to confirm (e.g., "cui-gitea-prod")
```

**If ANY check fails**: STOP immediately and investigate discrepancy.

---

## Environment Selection Protocol

### Supported Environments

| Environment | Project ID | Purpose | Risk Level |
|-------------|-----------|---------|------------|
| **Development** | dcg-gitea-dev | Testing, experimentation | LOW |
| **Staging** | dcg-gitea-stage | Pre-production validation | MEDIUM |
| **Production** | cui-gitea-prod | Live production system | **CRITICAL** |

### Safe Environment Switching Procedure

**Method 1: Using environment-selector.sh (Recommended)**
```bash
cd /home/notme/Desktop/code/DCG/gitea
./scripts/environment-selector.sh [dev|staging|prod]

# Interactive prompts will guide you through:
# 1. Confirmation of target environment
# 2. gcloud project switch
# 3. Terraform backend reinitialization
# 4. Variable file selection
# 5. Validation of new context
```

**Method 2: Manual Switching (Advanced)**
```bash
# Step 1: Set GCloud project
gcloud config set project <project-id>
gcloud config get-value project  # Verify

# Step 2: Navigate to Terraform directory
cd /home/notme/Desktop/code/DCG/gitea/terraform/gcp-gitea

# Step 3: Initialize Terraform with correct backend
terraform init -reconfigure \
  -backend-config="bucket=<project-id>-gitea-tfstate-<suffix>" \
  -backend-config="prefix=terraform/state"

# Step 4: Verify state
terraform show | grep project_id | head -5

# Step 5: Source environment variables (optional)
source .env.<environment>
```

### Production Environment Special Requirements

Production operations require:
1. **Peer Review**: Second team member must review plan
2. **Change Request**: Formal CR ticket in system
3. **Backup Verification**: Confirm recent backup exists
4. **Typed Confirmation**: Must type full project ID "cui-gitea-prod"
5. **Time Window**: Only during approved maintenance windows
6. **Rollback Plan**: Document rollback procedure before proceeding

---

## Terraform Variable Hierarchy

### Understanding Variable Precedence (Lowest to Highest)

```
1. Default values in *.tf files               (LOWEST PRIORITY)
2. environment-specific .tfvars files
3. terraform.tfvars (AUTO-LOADED)             ⚠️ DANGEROUS - DO NOT USE
4. -var-file=<file> (explicit parameter)
5. TF_VAR_* environment variables
6. -var command-line flags                    (HIGHEST PRIORITY)
```

### Critical Rule: **NEVER Use Auto-Loaded terraform.tfvars**

**❌ WRONG** (relies on auto-loading):
```bash
terraform plan    # Uses terraform.tfvars automatically
terraform apply   # DANGEROUS - which project is this?
```

**✅ CORRECT** (explicit variable file):
```bash
terraform plan -var-file=terraform.tfvars.prod    # Explicit = safe
terraform apply -var-file=terraform.tfvars.prod
```

### Variable File Naming Convention

```
terraform.tfvars.dev      # Development environment
terraform.tfvars.staging  # Staging environment
terraform.tfvars.prod     # Production environment
terraform.tfvars.example  # Template (no real values)
terraform.tfvars          # ⚠️ NEVER USE - Too ambiguous
```

**Git Policy:**
- `terraform.tfvars` is gitignored (ambiguous, environment-specific)
- `terraform.tfvars.{dev,staging,prod}` are tracked (explicit, team-shared)
- `terraform.tfvars.example` is tracked (documentation template)

---

## Project Verification Commands

### Essential Verification Commands

```bash
# ===== GCloud Context =====
gcloud config get-value project
# Output: cui-gitea-prod

gcloud config get-value account
# Verify correct Google account active

# ===== Terraform Context =====
terraform workspace show
# Output: default (or environment name)

terraform show | grep -E "project_id|project =" | head -10
# Verify all resources show correct project

terraform state list | head -20
# Verify resource names contain correct project prefix

# ===== Backend Validation =====
grep bucket backend.tf
# Verify state bucket matches project

# ===== Variable Files =====
ls -lh terraform.tfvars*
# List all variable files with timestamps

grep project_id terraform.tfvars.prod
# Verify specific variable file contains correct project

# ===== Resource Counting =====
terraform state list | wc -l
# Count current resources in state

terraform plan -destroy | grep "to destroy" | head -1
# Preview destruction count
```

### Validation Script (Automated)

```bash
# Run comprehensive validation
cd /home/notme/Desktop/code/DCG/gitea
./scripts/terraform-project-validator.sh

# Output will show:
# ✅ GCloud Project: cui-gitea-prod
# ✅ Terraform State: cui-gitea-prod
# ✅ Backend Bucket: cui-gitea-prod-gitea-tfstate-f5f2e413
# ✅ Resource Sample: All contain cui-gitea-prod
# ✅ Variable File: terraform.tfvars.prod → cui-gitea-prod
# ✅ VALIDATION PASSED
```

---

## Destruction Safety Protocol

### CRITICAL: Destruction Operations

Destruction is **IRREVERSIBLE** for most resources. Follow this protocol exactly.

#### Phase 1: Pre-Destruction (Mandatory)

```bash
# 1. Ensure you're in correct directory
cd /home/notme/Desktop/code/DCG/gitea/terraform/gcp-gitea

# 2. Run validation script
../../../scripts/terraform-project-validator.sh --operation=destroy

# 3. Verify gcloud project explicitly
EXPECTED_PROJECT="cui-gitea-prod"  # Set your target
ACTUAL_PROJECT=$(gcloud config get-value project)

if [ "$ACTUAL_PROJECT" != "$EXPECTED_PROJECT" ]; then
    echo "❌ PROJECT MISMATCH!"
    echo "Expected: $EXPECTED_PROJECT"
    echo "Actual: $ACTUAL_PROJECT"
    exit 1
fi

# 4. Generate destroy plan with explicit variables
terraform plan -destroy \
  -var-file=terraform.tfvars.prod \
  -out=destroy.tfplan

# 5. Review plan - check for wrong project
terraform show destroy.tfplan | grep -E "will be destroyed" | head -20
terraform show destroy.tfplan | grep -c "dcg-gitea-stage"  # Should be 0
terraform show destroy.tfplan | grep -c "cui-gitea-prod"   # Should be 100+

# 6. Count resources
DESTROY_COUNT=$(terraform show destroy.tfplan | grep -c "# google")
echo "Resources to destroy: $DESTROY_COUNT"

# Validate count is within expected range
if [ $DESTROY_COUNT -lt 80 ] || [ $DESTROY_COUNT -gt 120 ]; then
    echo "⚠️ WARNING: Unexpected resource count!"
    echo "Expected: 80-120, Got: $DESTROY_COUNT"
    read -p "Proceed anyway? (yes/no): " confirm
fi
```

#### Phase 2: Confirmation (Required)

```bash
# Double confirmation required for production
echo "You are about to DESTROY resources in: $EXPECTED_PROJECT"
echo "This action is IRREVERSIBLE."
echo ""
read -p "Type the FULL project ID to confirm: " typed_project

if [ "$typed_project" != "$EXPECTED_PROJECT" ]; then
    echo "❌ Confirmation failed. Aborting."
    exit 1
fi

# Second confirmation
read -p "Type 'DESTROY' in all caps to proceed: " typed_word
if [ "$typed_word" != "DESTROY" ]; then
    echo "❌ Second confirmation failed. Aborting."
    exit 1
fi

echo "✅ Double confirmation received. Proceeding..."
sleep 3  # 3-second abort window
```

#### Phase 3: Execution (Monitored)

```bash
# Execute destruction using pre-approved plan
terraform apply destroy.tfplan 2>&1 | tee /tmp/destroy_execution_$(date +%Y%m%d_%H%M%S).log

# Monitor output in real-time
# Watch for resource names to confirm correct project
# CTRL+C to abort if anything looks wrong

# After completion, verify
gcloud compute instances list --project=$EXPECTED_PROJECT
# Should be empty or show expected remaining resources
```

#### Phase 4: Post-Destruction Verification (Required)

```bash
# Verify expected resources destroyed
gcloud compute instances list --project=$EXPECTED_PROJECT
gcloud compute disks list --project=$EXPECTED_PROJECT
gcloud storage buckets list --project=$EXPECTED_PROJECT

# Generate destruction evidence report
cat > /tmp/destruction_complete_$(date +%Y%m%d_%H%M%S).md <<EOF
# Destruction Complete

**Project**: $EXPECTED_PROJECT
**Date**: $(date)
**Resources Destroyed**: $DESTROY_COUNT
**Operator**: $(whoami)
**Evidence Log**: /tmp/destroy_execution_*.log

## Verification
- Compute instances: $(gcloud compute instances list --project=$EXPECTED_PROJECT | wc -l)
- Disks: $(gcloud compute disks list --project=$EXPECTED_PROJECT | wc -l)
- Buckets: $(gcloud storage buckets list --project=$EXPECTED_PROJECT | wc -l)

## Status
Destruction completed successfully.
EOF
```

### Using Safe Wrapper Script

**Recommended**: Use the enhanced gcp-destroy.sh script with built-in validation:

```bash
cd /home/notme/Desktop/code/DCG/gitea

# Destruction with full validation
./scripts/gcp-destroy.sh \
  --project=cui-gitea-prod \
  --environment=prod \
  --confirm-project=cui-gitea-prod \
  --expected-resources=100 \
  --keep-evidence \
  --backup \
  --verbose

# Script will automatically:
# 1. Run validation checks
# 2. Generate destroy plan
# 3. Require double confirmation
# 4. Execute destruction
# 5. Generate evidence report
# 6. Create audit log entry
```

---

## Common Pitfalls

### ❌ Mistake 1: Auto-Loading terraform.tfvars

**What Happens:**
```bash
# Working directory has terraform.tfvars with project_id="dcg-gitea-stage"
terraform destroy  # Oops - destroys staging, not production!
```

**Why It's Dangerous:**
- terraform.tfvars is automatically loaded without explicit parameter
- Easy to forget which project it's configured for
- No visual indication of which environment is active

**Solution:**
```bash
# Always use explicit -var-file parameter
terraform destroy -var-file=terraform.tfvars.prod  # Clear and explicit
```

### ❌ Mistake 2: Reusing Working Directory

**What Happens:**
```bash
# Yesterday: worked on staging
cd terraform/gcp-gitea
terraform apply -var-file=terraform.tfvars.staging

# Today: want to work on production
# But backend still points to staging!
terraform apply -var-file=terraform.tfvars.prod  # Uses WRONG state!
```

**Solution:**
```bash
# Always reinitialize when switching environments
terraform init -reconfigure \
  -backend-config="bucket=cui-gitea-prod-gitea-tfstate-f5f2e413"
```

### ❌ Mistake 3: Trusting gcloud Config Alone

**What Happens:**
```bash
gcloud config set project cui-gitea-prod  # Set gcloud
# But terraform state still points to staging backend!
terraform destroy  # Destroys wrong project!
```

**Why It Fails:**
- Terraform doesn't use gcloud config
- Terraform uses backend.tf configuration
- Two separate contexts can diverge

**Solution:**
```bash
# Verify BOTH contexts match
gcloud config get-value project          # cui-gitea-prod
terraform show | grep project_id | head  # cui-gitea-prod
# Both must match!
```

### ❌ Mistake 4: Skipping Plan Review

**What Happens:**
```bash
terraform destroy -auto-approve  # NEVER DO THIS
# Destroys resources without showing you what will be destroyed!
```

**Solution:**
```bash
# Always generate and review plan first
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan | less  # Review everything
terraform apply destroy.tfplan         # Only if plan is correct
```

### ❌ Mistake 5: Assuming Resource Names Are Safe

**What Happens:**
```bash
# See resource names like: dcg-gitea-stage-staging-vm
# Think: "This is fine, I'm working on staging"
# But actually intending to work on production!
```

**Solution:**
```bash
# Validate resource names match INTENDED target, not just current state
grep "cui-gitea-prod" destroy.tfplan  # For production
grep "dcg-gitea-stage" destroy.tfplan # Should be 0 if targeting prod
```

---

## Emergency Rollback

### If You Realize Mid-Destruction You Targeted Wrong Project

#### Immediate Actions (Within 30 Seconds)

1. **PRESS CTRL+C IMMEDIATELY** to attempt to stop Terraform
   - May not stop all deletions in progress
   - Some resources may already be destroyed

2. **Check what's been destroyed so far:**
   ```bash
   terraform state list > /tmp/remaining_resources.txt
   # Compare to backup state
   ```

3. **DO NOT run any more Terraform commands**
   - Don't try to "fix" with terraform apply
   - Don't run terraform destroy again

#### Recovery Steps (First Hour)

1. **Assess damage:**
   ```bash
   # List remaining resources
   gcloud compute instances list --project=<wrong-project>
   gcloud compute disks list --project=<wrong-project>
   gcloud storage buckets list --project=<wrong-project>
   ```

2. **Check for evidence bucket (usually protected):**
   ```bash
   gsutil ls gs://<project>-prod-evidence-*
   # Evidence bucket should be retained due to 7-year retention policy
   ```

3. **Retrieve last known good state:**
   ```bash
   # State is in GCS bucket (versioned)
   gsutil cp gs://<project>-gitea-tfstate-*/terraform/state/default.tfstate \
     /tmp/last_good_state.tfstate
   ```

4. **Begin restoration:**
   - Follow GCP_DISASTER_RECOVERY.md procedures
   - Use terraform import for critical resources
   - Restore from backups if available

#### Prevention for Future

1. **Enable terminal logging:**
   ```bash
   script -a /tmp/terraform_session_$(date +%Y%m%d_%H%M%S).log
   # All commands will be logged
   ```

2. **Use tmux/screen:**
   - Prevents accidental terminal closure during operations
   - Allows reconnection if SSH session drops

3. **Set up safety alias:**
   ```bash
   # Add to ~/.bashrc
   alias tf-destroy='echo "Use make destroy-with-validation instead!" && return 1'
   ```

---

## Approval Workflow

### When Peer Review is Required

**Mandatory peer review for:**
- ✅ Any production destruction operation
- ✅ Operations affecting >50 resources
- ✅ Changes to security configurations (IAM, KMS, firewalls)
- ✅ State file migrations
- ✅ Backend reconfigurations

**Optional but recommended for:**
- Staging environment destructive changes
- New resource deployments in production
- Terraform version upgrades

### Peer Review Process

1. **Requester Actions:**
   ```bash
   # Generate plan
   terraform plan -destroy -var-file=terraform.tfvars.prod -out=destroy.tfplan

   # Create review package
   terraform show destroy.tfplan > /tmp/destroy_plan_review.txt

   # Share with peer
   # - Copy of plan file
   # - List of resources to be destroyed
   # - Justification document
   # - Rollback procedure
   ```

2. **Reviewer Actions:**
   ```bash
   # Verify intended project
   grep -E "project.*=" /tmp/destroy_plan_review.txt | head -10

   # Check resource count
   grep -c "# google" /tmp/destroy_plan_review.txt

   # Spot check critical resources
   grep -E "(kms|secret|storage_bucket)" /tmp/destroy_plan_review.txt

   # Approve or reject
   # If approved: Sign off in change request ticket
   ```

3. **Execution:**
   - Only proceed after written approval
   - Screenshot approval for audit trail
   - Log approval in environment-audit.log

---

## Incident Response

### If Accidental Destruction Occurs

#### Severity Classification

**P0 - Critical** (Production data loss, customer impact)
- Immediate escalation
- All hands on deck
- Executive notification

**P1 - High** (Production service disruption, no data loss)
- Notify team lead
- Begin recovery procedures
- Post-mortem required

**P2 - Medium** (Staging/dev destruction)
- Notify team
- Recovery when possible
- Lessons learned document

**P3 - Low** (Non-critical resources, easily recreated)
- Self-recovery
- Update runbooks if needed

#### Incident Response Steps

1. **Declare Incident** (within 5 minutes of detection)
   ```bash
   # Send alert
   echo "INCIDENT: Accidental destruction of <project>" | \
     mail -s "P1: GCP Resource Destruction" team@company.com
   ```

2. **Stop Further Damage** (immediate)
   - CTRL+C any running Terraform
   - Revoke operator credentials temporarily
   - Lock state file
   ```bash
   gsutil -m acl ch -u operator@email.com:R gs://state-bucket/*
   ```

3. **Assess Impact** (within 15 minutes)
   - List destroyed vs remaining resources
   - Check for data backups
   - Estimate recovery time

4. **Begin Recovery** (within 30 minutes)
   - Follow GCP_DISASTER_RECOVERY.md
   - Restore from backups
   - Use terraform import for resources

5. **Root Cause Analysis** (within 24 hours)
   - Why did safeguards fail?
   - What process broke down?
   - What additional controls are needed?

6. **Post-Incident Review** (within 1 week)
   - Document timeline
   - Update procedures
   - Implement new safeguards
   - Team training on lessons learned

---

## Quick Reference

### Safe Destruction Checklist (Printable)

```
╔══════════════════════════════════════════════════════════╗
║         SAFE TERRAFORM DESTRUCTION CHECKLIST            ║
╠══════════════════════════════════════════════════════════╣
║ Project: _________________________________________      ║
║ Date: ______________ Operator: ___________________      ║
║                                                          ║
║ PRE-FLIGHT VALIDATION                                    ║
║ [ ] 1. Working directory correct                        ║
║ [ ] 2. GCloud project matches intent                    ║
║ [ ] 3. Terraform backend verified                       ║
║ [ ] 4. Using explicit -var-file parameter               ║
║ [ ] 5. Terraform state shows correct project            ║
║ [ ] 6. Resource names match target project              ║
║ [ ] 7. Destroy plan generated and reviewed              ║
║ [ ] 8. Wrong project name not in plan (grep = 0)        ║
║ [ ] 9. Resource count validated                         ║
║ [ ] 10. Double confirmation obtained                    ║
║                                                          ║
║ EXECUTION SAFETY                                         ║
║ [ ] Peer review completed (if production)               ║
║ [ ] Recent backup verified                              ║
║ [ ] Rollback plan documented                            ║
║ [ ] Typed confirmation: ___________________________     ║
║ [ ] Second confirmation: "DESTROY"                      ║
║                                                          ║
║ POST-DESTRUCTION                                         ║
║ [ ] Resources verified destroyed                        ║
║ [ ] Evidence report generated                           ║
║ [ ] Audit log updated                                   ║
║ [ ] Peer notified of completion                         ║
║                                                          ║
║ SIGNATURES                                               ║
║ Operator: _________________________ Date: ____________  ║
║ Reviewer: _________________________ Date: ____________  ║
╚══════════════════════════════════════════════════════════╝
```

### Command Quick Reference

```bash
# Validation Commands (run before ANY operation)
gcloud config get-value project                    # Verify gcloud
terraform show | grep project_id | head           # Verify state
./scripts/terraform-project-validator.sh          # Full validation

# Safe Environment Switch
./scripts/environment-selector.sh [dev|staging|prod]

# Safe Destruction
make destroy-with-validation PROJECT_ID=cui-gitea-prod ENVIRONMENT=prod

# Emergency Stop
CTRL+C                                            # Stop Terraform
terraform state lock <state-bucket>                # Lock state

# Recovery
./scripts/gcp-restore.sh -p <project> -e <env>    # Restore from backup
```

### Support Contacts

| Issue | Contact | Response Time |
|-------|---------|---------------|
| **Accidental Destruction** | team@company.com | Immediate |
| **Validation Script Failures** | devops@company.com | 1 hour |
| **Procedure Questions** | See GCP_OPERATIONS_RUNBOOK.md | N/A |
| **Training Requests** | training@company.com | 1 week |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-13 | Claude AI | Initial version based on INC-2025-1013-001 |

---

## Appendix A: Terraform Variable Precedence Deep Dive

### How Terraform Loads Variables (In Order)

1. **Environment Variables** (`TF_VAR_name`)
   ```bash
   export TF_VAR_project_id="cui-gitea-prod"
   terraform plan  # Will use cui-gitea-prod
   ```

2. **terraform.tfvars** (auto-loaded from current directory)
   ```bash
   # If file exists, it's automatically loaded - NO EXPLICIT REFERENCE NEEDED
   # This is why it's dangerous!
   ```

3. **terraform.tfvars.json** (auto-loaded)

4. ***.auto.tfvars** (any files matching pattern, alphabetically)

5. **-var-file** flag (explicit)
   ```bash
   terraform plan -var-file=terraform.tfvars.prod
   ```

6. **-var** flag (highest precedence)
   ```bash
   terraform plan -var="project_id=cui-gitea-prod"
   ```

### Recommended Approach

**Use -var-file exclusively:**
```bash
# Explicit and obvious which environment
terraform plan -var-file=terraform.tfvars.prod
terraform apply -var-file=terraform.tfvars.prod
```

**Avoid environment variables for project selection:**
- Hard to debug
- Not visible in command history
- Easy to forget they're set

---

## Appendix B: State File Management

### Backend Configuration Best Practices

```hcl
# backend.tf
terraform {
  backend "gcs" {
    bucket = "cui-gitea-prod-gitea-tfstate-f5f2e413"
    prefix = "terraform/state"
  }
}
```

**Key Points:**
- Bucket name should contain project ID
- Enable versioning on state bucket
- Enable object locking for critical environments
- Regular state backups

### State Locking

```bash
# Manually lock state to prevent concurrent operations
gsutil setmeta -h "x-goog-meta-lock:1" \
  gs://cui-gitea-prod-gitea-tfstate-f5f2e413/terraform/state/default.tfstate

# Unlock
gsutil setmeta -h "x-goog-meta-lock:" \
  gs://cui-gitea-prod-gitea-tfstate-f5f2e413/terraform/state/default.tfstate
```

---

**END OF SAFE OPERATIONS GUIDE**

*For questions or improvements to this guide, submit a pull request or contact the DevOps team.*
