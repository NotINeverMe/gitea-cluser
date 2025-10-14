# Safety Training Guide
## New Team Member Onboarding for DCG Gitea Infrastructure

**Document Version**: 1.0
**Created**: 2025-10-13
**Status**: MANDATORY TRAINING
**Completion Required**: Before any infrastructure operations
**Estimated Time**: 45-60 minutes

---

## Table of Contents

1. [Welcome & Safety Culture](#welcome--safety-culture)
2. [Critical Incident Case Study](#critical-incident-case-study)
3. [Safety Infrastructure Overview](#safety-infrastructure-overview)
4. [Mandatory Procedures](#mandatory-procedures)
5. [Common Pitfalls & How to Avoid Them](#common-pitfalls--how-to-avoid-them)
6. [Validation Checklist](#validation-checklist)
7. [Emergency Procedures](#emergency-procedures)
8. [Knowledge Check Quiz](#knowledge-check-quiz)
9. [Certification](#certification)

---

## Welcome & Safety Culture

### The DCG Infrastructure Philosophy

Welcome to the DCG Gitea Infrastructure team. Before you run your first Terraform command, we want you to understand something critical: **infrastructure operations are powerful, and mistakes can be costly**.

In cloud infrastructure management, a single command can:
- Create or destroy hundreds of resources
- Affect production systems serving real users
- Cost thousands of dollars
- Take hours or days to recover from

### Our Safety Culture

At DCG, we prioritize safety over speed. Our core principles are:

**1. Verify Before Execute**
- Never assume you know which environment is active
- Always validate your context before running commands
- Use our validation tools - they exist for a reason

**2. Explicit Is Better Than Implicit**
- Always specify exactly what you're doing
- Use explicit parameters (never rely on auto-loading)
- If you're not 100% certain, ask or check

**3. No Blame for Asking Questions**
- It's always better to ask than to guess
- Questions prevent incidents
- Every team member, regardless of experience, asks questions

**4. Better Slow and Safe Than Fast and Wrong**
- Speed doesn't matter if you destroy the wrong environment
- Taking 2 extra minutes for validation can save 6 hours of recovery
- Our tools are designed for safety, not convenience

**5. Learn From Every Incident**
- We document incidents not to assign blame, but to prevent recurrence
- Every incident teaches us how to improve our processes
- You're about to learn from a real incident that happened on October 13, 2025

### What This Training Covers

By the end of this training, you will:
- Understand how a real infrastructure incident occurred and why
- Know which safety tools are available and when to use them
- Be able to identify common pitfalls before they cause problems
- Have a checklist for safe operations
- Know what to do in an emergency
- Be certified to perform infrastructure operations

---

## Critical Incident Case Study

### The dcg-gitea-stage Incident

**Date**: October 13, 2025
**Time**: 14:23 UTC
**Duration**: 6 hours from detection to full restoration
**Severity**: P1 (High) - Service disruption, no data loss
**Impact**: 86 resources destroyed, 4-6 hours downtime
**Cost**: $0 data loss, but significant operational impact

### What Was Supposed To Happen

The operator's goal was straightforward:
1. Decommission the `cui-gitea-prod` production environment (no longer needed)
2. Destroy all resources in that project
3. Document the decommissioning for compliance

This was a legitimate, planned operation with proper authorization.

### What Actually Happened

Instead of destroying `cui-gitea-prod`, **the operator accidentally destroyed all 86 resources in `dcg-gitea-stage`** (the active staging environment).

### The Timeline

**14:23 UTC** - Operator begins decommissioning process
```bash
# Operator sets GCloud project
gcloud config set project cui-gitea-prod
gcloud config get-value project
# Output: cui-gitea-prod ✓

# Navigates to terraform directory
cd /home/notme/Desktop/code/DCG/gitea/terraform/gcp-gitea

# Generates destroy plan
terraform plan -destroy -var-file=terraform.tfvars.prod -out=destroy.tfplan
```

**14:25 UTC** - Reviews plan output
```
Plan: 0 to add, 0 to change, 86 to destroy.

Terraform will perform the following actions:

  # google_compute_instance.gitea_vm will be destroyed
  - resource "google_compute_instance" "gitea_vm" {
      - name         = "dcg-gitea-stage-staging-gitea-vm"
      ...
    }
```

**Critical Mistake**: The operator saw `dcg-gitea-stage` in the resource names but thought:
- "These resource names must be wrong in the plan output"
- "My gcloud project is set to cui-gitea-prod"
- "My tfvars file specifies cui-gitea-prod"
- "The plan must be showing old resource names"

Instead of stopping to investigate, the operator continued.

**14:27 UTC** - Applies destroy plan
```bash
terraform apply destroy.tfplan
```

**14:28 UTC** - Destruction begins
```
google_compute_disk.data_disk: Destroying... [id=dcg-gitea-stage-staging-data-disk]
google_compute_instance.gitea_vm: Destroying... [id=dcg-gitea-stage-staging-gitea-vm]
google_compute_firewall.gitea_ssh: Destroying...
```

**14:29 UTC** - Operator notices the problem
```
Destroy complete! Resources: 86 destroyed.
```

The operator checks the staging environment and realizes: **staging is gone, production is still running**.

**14:30 UTC** - Incident declared, recovery begins

**18:45 UTC** - Full recovery completed
- All 86 resources recreated
- State files restored from backup
- Services validated and operational

### Root Cause Analysis

After investigation, we identified the root cause:

**The Terraform backend was pointed to the wrong state bucket.**

Here's what the operator didn't understand:

```
┌──────────────────────────────────────────────────────┐
│ What the Operator Checked                            │
├──────────────────────────────────────────────────────┤
│ ✓ gcloud config get-value project → cui-gitea-prod  │
│ ✓ terraform.tfvars.prod → project_id = cui-gitea-prod│
│ ✓ Authorization: Manager approved decommissioning    │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│ What the Operator Didn't Check                       │
├──────────────────────────────────────────────────────┤
│ ✗ Terraform backend configuration (backend.tf)       │
│ ✗ Which state bucket Terraform was using             │
│ ✗ Terraform state resources (terraform state list)   │
│ ✗ Validation script output                           │
└──────────────────────────────────────────────────────┘
```

The `backend.tf` file looked like this:
```hcl
terraform {
  backend "gcs" {
    bucket = "dcg-gitea-stage-gitea-tfstate-a3f8b229"  # WRONG!
    prefix = "terraform/state"
  }
}
```

**The backend was hardcoded to the staging state bucket from previous work.**

Even though the operator specified `-var-file=terraform.tfvars.prod`, Terraform read the state from the staging bucket and destroyed staging resources.

### The Critical Misunderstanding

Many people think: **"If I set the gcloud project and use the right tfvars file, I'm safe."**

**THIS IS WRONG.**

Terraform operations depend on THREE separate contexts:

1. **GCloud Configuration** - For authentication
2. **Terraform Backend** - For state storage (determines WHICH environment)
3. **Terraform Variables** - For resource configuration values

All three must align. If any one is wrong, you can destroy the wrong environment.

### What Should Have Happened

If the operator had followed the mandatory procedures:

**Step 1**: Run validation script
```bash
./scripts/terraform-project-validator.sh --operation=destroy
```

**Output would have shown**:
```
❌ VALIDATION FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Context Mismatch Detected:
  GCloud Project:        cui-gitea-prod
  Terraform Backend:     dcg-gitea-stage-gitea-tfstate-a3f8b229
  State Resources:       dcg-gitea-stage-*

ERROR: Your Terraform backend is configured for dcg-gitea-stage,
but your gcloud project is set to cui-gitea-prod.

This mismatch will cause operations to affect dcg-gitea-stage
regardless of your gcloud or tfvars settings.

STOP: Do not proceed until contexts are aligned.
```

The validation script would have **prevented the entire incident**.

### Five Critical Lessons Learned

**Lesson 1: Terraform Backend is the Source of Truth**
- The backend configuration determines which environment you're operating on
- GCloud config and tfvars don't override the backend
- Always verify backend matches your intent

**Lesson 2: Never Skip Validation**
- Validation scripts exist because incidents like this happen
- 2 minutes of validation saves 6 hours of recovery
- If a validation script fails, STOP and investigate

**Lesson 3: Resource Names in Plans Are Not "Wrong"**
- If you see unexpected resource names in a plan, that's a RED FLAG
- Don't rationalize it away ("must be old data")
- Unexpected output means something is misconfigured

**Lesson 4: Multiple Checks Are Required**
- Checking one context (gcloud) is not enough
- All three contexts (gcloud, backend, variables) must align
- Use the validation tools that check all contexts

**Lesson 5: When In Doubt, Stop and Ask**
- If anything looks unexpected, pause
- Ask a senior engineer to review
- It's always better to ask than to proceed with uncertainty

### Safeguards Implemented After This Incident

After this incident, we implemented several new safeguards:

1. **Mandatory Validation Scripts**
   - `terraform-project-validator.sh` - Must be run before operations
   - `pre-destroy-validator.sh` - Specifically for destruction operations
   - Both scripts now run automatically in Makefile targets

2. **Enhanced Documentation**
   - `SAFE_OPERATIONS_GUIDE.md` - Comprehensive safety procedures
   - `ENVIRONMENT_MANAGEMENT.md` - Environment isolation strategies
   - This training document you're reading right now

3. **Git Pre-Commit Hooks**
   - Warns if backend.tf doesn't match expected project
   - Prevents committing terraform.tfvars (ambiguous filename)
   - Validates that explicit -var-file is used in scripts

4. **Makefile Safety Targets**
   - `make show-environment` - Shows all three contexts
   - `make verify-project` - Validates gcloud matches Makefile
   - `make safe-destroy` - Destruction with all validation steps

5. **Environment Selector Script**
   - `environment-selector.sh` - Safely switch between environments
   - Automatically reconfigures all three contexts
   - Interactive confirmation at each step

6. **Mandatory Training**
   - This document is now required reading for all team members
   - Knowledge check quiz must be passed
   - Certification signed off by manager

### The Most Important Takeaway

**This incident was 100% preventable.**

Every safeguard that would have prevented it existed before the incident occurred. The operator simply didn't use them.

Don't be that operator. Use the tools. Follow the procedures. Ask questions.

---

## Safety Infrastructure Overview

You are not alone in maintaining safety. We have built multiple tools and documentation to help you operate safely.

### Core Safety Documents

#### 1. SAFE_OPERATIONS_GUIDE.md
**Location**: `/home/notme/Desktop/code/DCG/gitea/docs/SAFE_OPERATIONS_GUIDE.md`

**What it covers**:
- Pre-flight checklist (10 mandatory checks before operations)
- Environment selection protocol
- Terraform variable hierarchy and precedence
- Destruction safety protocol (4 phases)
- Common pitfalls and how to avoid them
- Emergency rollback procedures
- Approval workflows for production
- Incident response procedures

**When to use it**:
- Before ANY Terraform operation that modifies resources
- Before ANY destruction operation
- When switching between environments
- When troubleshooting unexpected behavior
- As reference material during operations

#### 2. ENVIRONMENT_MANAGEMENT.md
**Location**: `/home/notme/Desktop/code/DCG/gitea/docs/ENVIRONMENT_MANAGEMENT.md`

**What it covers**:
- Overview of all environments (dev, staging, prod)
- Environment isolation strategy
- Configuration file structure
- Environment switching procedures
- Variable file naming conventions
- The three contexts that must align
- Real-world incident analysis (dcg-gitea-stage)

**When to use it**:
- When you need to switch environments
- When setting up a new environment
- When troubleshooting environment-related issues
- Understanding the relationship between contexts

### Validation Scripts

#### 1. terraform-project-validator.sh
**Location**: `/home/notme/Desktop/code/DCG/gitea/scripts/terraform-project-validator.sh`

**What it does**:
- Validates GCloud active project
- Checks Terraform backend configuration
- Inspects current state resources
- Compares all three contexts
- Reports any mismatches

**When to use it**:
```bash
# Before any Terraform operation
./scripts/terraform-project-validator.sh

# Before specific operations
./scripts/terraform-project-validator.sh --operation=destroy

# Targeting specific project
./scripts/terraform-project-validator.sh --project=dcg-gitea-stage
```

**Example output when contexts match**:
```
✅ PROJECT VALIDATION PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GCloud Project:        dcg-gitea-stage
Terraform Backend:     dcg-gitea-stage-gitea-tfstate-a3f8b229
Variable File:         terraform.tfvars.staging
State Resources:       dcg-gitea-stage-* (86 resources)

✅ All contexts aligned. Safe to proceed.
```

**Example output when contexts don't match**:
```
❌ VALIDATION FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Context Mismatch Detected:
  GCloud Project:        cui-gitea-prod
  Terraform Backend:     dcg-gitea-stage-gitea-tfstate-a3f8b229
  State Resources:       dcg-gitea-stage-*

ERROR: Contexts do not align.

STOP: Do not proceed until this is resolved.
```

#### 2. pre-destroy-validator.sh
**Location**: `/home/notme/Desktop/code/DCG/gitea/scripts/pre-destroy-validator.sh`

**What it does**:
- All checks from terraform-project-validator.sh
- Generates destroy plan
- Counts resources to be destroyed
- Searches for wrong project names in plan
- Requires explicit confirmation
- Creates pre-destruction snapshot

**When to use it**:
```bash
# Before ANY destroy operation
./scripts/pre-destroy-validator.sh \
  --project=dcg-gitea-stage \
  --var-file=terraform.tfvars.staging
```

**Safety checks performed**:
1. Validates all three contexts align
2. Generates destroy plan with explicit var-file
3. Counts resources to be destroyed
4. Searches destroy plan for unexpected project names
5. Compares resource count against expected range
6. Requires typing full project ID to confirm
7. Creates evidence snapshot before destruction
8. Logs all operations for audit trail

#### 3. environment-selector.sh
**Location**: `/home/notme/Desktop/code/DCG/gitea/scripts/environment-selector.sh`

**What it does**:
- Safely switches between environments
- Updates all three contexts automatically
- Validates each step
- Interactive confirmation prompts

**When to use it**:
```bash
# Switch to staging environment
./scripts/environment-selector.sh staging

# Switch to development environment
./scripts/environment-selector.sh dev
```

**What it automates**:
1. Prompts for confirmation of target environment
2. Sets gcloud project
3. Verifies gcloud project change
4. Backs up current backend.tf
5. Updates backend.tf with new state bucket
6. Runs `terraform init -reconfigure`
7. Validates state matches new environment
8. Displays summary of new context

**This is the RECOMMENDED way to switch environments.**

#### 4. gcp-destroy.sh
**Location**: `/home/notme/Desktop/code/DCG/gitea/scripts/gcp-destroy.sh`

**What it does**:
- Wrapper for safe destruction operations
- Integrates all validation checks
- Enforces double confirmation
- Creates evidence logs
- Performs post-destruction verification

**When to use it**:
```bash
# Safe destruction with all checks
./scripts/gcp-destroy.sh \
  --project=dcg-gitea-stage \
  --environment=staging \
  --confirm-project=dcg-gitea-stage \
  --var-file=terraform.tfvars.staging \
  --keep-evidence \
  --backup \
  --verbose
```

**This is the RECOMMENDED way to perform destruction operations.**

### Git Hooks

#### Pre-Commit Hook
**Location**: `.git/hooks/pre-commit`

**What it checks**:
- Warns if committing terraform.tfvars (should use .tfvars.{env})
- Validates Terraform formatting
- Checks for potential secrets in code
- Verifies documentation is up to date

#### Pre-Push Hook
**Location**: `.git/hooks/pre-push`

**What it checks**:
- Runs terraform validation
- Checks for uncommitted changes
- Verifies branch naming conventions

### Makefile Safety Targets

The Makefile includes several safety-focused targets:

```bash
# Display all three contexts
make show-environment

# Verify gcloud project matches Makefile PROJECT_ID
make verify-project

# Run full project validation
make validate-project

# Validate before destruction
make validate-destroy VAR_FILE=terraform.tfvars.staging

# Safe destruction with all checks
make safe-destroy ENVIRONMENT=staging VAR_FILE=terraform.tfvars.staging
```

**Always use Makefile targets when available** - they include safety checks automatically.

### Documentation Hierarchy

When you need help:

1. **Quick Reference**: `SAFE_OPERATIONS_GUIDE.md` - Quick Reference section
2. **Standard Operations**: `SAFE_OPERATIONS_GUIDE.md` - Full procedures
3. **Environment Issues**: `ENVIRONMENT_MANAGEMENT.md`
4. **Emergency**: `SAFE_OPERATIONS_GUIDE.md` - Emergency Rollback section
5. **Disaster Recovery**: `GCP_DISASTER_RECOVERY.md`

---

## Mandatory Procedures

These procedures are **MANDATORY** for all infrastructure operations. Failure to follow these procedures can result in incidents.

### Procedure 1: NEVER Use terraform destroy Without Validation

**❌ WRONG - Direct destruction**:
```bash
terraform destroy -var-file=terraform.tfvars.prod
```

**✅ CORRECT - Validated destruction**:
```bash
# Step 1: Validate context
./scripts/terraform-project-validator.sh --operation=destroy

# Step 2: Use validation script for destruction
./scripts/pre-destroy-validator.sh \
  --project=dcg-gitea-stage \
  --var-file=terraform.tfvars.staging

# OR use Makefile (recommended)
make safe-destroy ENVIRONMENT=staging VAR_FILE=terraform.tfvars.staging
```

**Why this matters**:
- Direct destruction bypasses all safety checks
- Validation scripts verify all three contexts align
- Pre-destroy validation creates evidence snapshots
- Takes 2 extra minutes, prevents 6-hour recovery

**No exceptions to this rule.**

### Procedure 2: ALWAYS Use Explicit -var-file Parameter

**❌ WRONG - Relying on auto-loading**:
```bash
terraform plan
terraform apply
```

**✅ CORRECT - Explicit variable file**:
```bash
terraform plan -var-file=terraform.tfvars.staging
terraform apply -var-file=terraform.tfvars.staging
```

**Why this matters**:
- `terraform.tfvars` is auto-loaded without you specifying it
- You can't tell which environment is active from the command
- Easy to forget which project is configured in auto-loaded file
- Explicit parameter makes it obvious in command history

**The file terraform.tfvars (without environment suffix) should never exist in your working directory.**

### Procedure 3: ALWAYS Verify gcloud Project Before Operations

**Before ANY operation that modifies resources**:
```bash
# Check current project
gcloud config get-value project

# If it doesn't match your intent, set it
gcloud config set project dcg-gitea-stage

# Verify it changed
gcloud config get-value project
```

**Why this matters**:
- GCloud project determines authentication and authorization
- Wrong project can cause API calls to fail or succeed unexpectedly
- Must match Terraform backend and variables for consistency

**Make this muscle memory.**

### Procedure 4: ALWAYS Review Destroy Plans Before Applying

**❌ WRONG - Auto-approve destruction**:
```bash
terraform destroy -auto-approve -var-file=terraform.tfvars.staging
```

**✅ CORRECT - Review then apply**:
```bash
# Generate plan
terraform plan -destroy -var-file=terraform.tfvars.staging -out=destroy.tfplan

# Review plan thoroughly
terraform show destroy.tfplan | less

# Check for wrong project names
terraform show destroy.tfplan | grep -c "cui-gitea-prod"  # Should be 0 for staging
terraform show destroy.tfplan | grep -c "dcg-gitea-stage"  # Should be >0 for staging

# Validate resource count
terraform show destroy.tfplan | grep "to destroy"

# Only apply if everything looks correct
terraform apply destroy.tfplan
```

**What to look for in the plan**:
1. Resource names match intended environment
2. Resource count is within expected range
3. No unexpected resources (wrong project)
4. Critical resources are included (if they should be destroyed)
5. Protected resources are NOT included (if they should stay)

**Red flags in a destroy plan**:
- Resource names don't match intended environment
- Resource count is significantly different than expected
- Resources from multiple projects appear
- Critical production resources appear when destroying staging

**If anything looks unexpected, STOP and investigate.**

### Procedure 5: ALWAYS Double-Check Project Names

Before executing any destructive operation:

```bash
# What you think you're targeting
INTENDED_PROJECT="dcg-gitea-stage"

# Check gcloud
GCLOUD_PROJECT=$(gcloud config get-value project)
echo "GCloud: $GCLOUD_PROJECT"

# Check backend
BACKEND_BUCKET=$(grep bucket terraform/gcp-gitea/backend.tf | awk -F'"' '{print $2}')
echo "Backend: $BACKEND_BUCKET"

# Check state resources
FIRST_RESOURCE=$(terraform state list | head -1)
echo "State: $FIRST_RESOURCE"

# Verify all contain intended project
echo "Verification:"
echo "$GCLOUD_PROJECT" | grep -q "$INTENDED_PROJECT" && echo "✓ GCloud matches" || echo "✗ GCloud MISMATCH"
echo "$BACKEND_BUCKET" | grep -q "$INTENDED_PROJECT" && echo "✓ Backend matches" || echo "✗ Backend MISMATCH"
echo "$FIRST_RESOURCE" | grep -q "$INTENDED_PROJECT" && echo "✓ State matches" || echo "✗ State MISMATCH"
```

**All three must match your intended project.**

If any don't match, use `environment-selector.sh` to fix the alignment.

### Procedure 6: NEVER Commit terraform.tfvars

**Files that should be committed**:
- `terraform.tfvars.dev`
- `terraform.tfvars.staging`
- `terraform.tfvars.prod`
- `terraform.tfvars.example`

**Files that should NOT be committed**:
- `terraform.tfvars` (no environment suffix - too ambiguous)
- Any file with secrets or sensitive data

**Why this matters**:
- `terraform.tfvars` is auto-loaded, making it dangerous
- It's ambiguous which environment it represents
- Committing it can cause other team members to accidentally use it
- Environment-suffixed files are explicit and safe

**The pre-commit hook will warn you, but you're responsible for understanding why.**

---

## Common Pitfalls & How to Avoid Them

### Pitfall 1: Relying on Auto-Loaded terraform.tfvars

**Why it's dangerous**:
- Terraform automatically loads `terraform.tfvars` without you specifying it
- You can't tell from your command which file is being used
- Easy to forget which project is configured in that file
- No visual indication of which environment is active
- Can be left over from previous work on different environment

**How it causes incidents**:
```bash
# Yesterday: You were working on staging
cd /home/notme/Desktop/code/DCG/gitea/terraform/gcp-gitea
echo 'project_id = "dcg-gitea-stage"' > terraform.tfvars
terraform apply
# Works fine

# Today: You want to work on production
# You forget about yesterday's terraform.tfvars file
terraform destroy  # Oops! Destroys staging, not production
```

**How to avoid it**:
1. **Never create terraform.tfvars** (without environment suffix)
2. **Always use explicit -var-file parameter**
3. Use environment-suffixed files: `terraform.tfvars.staging`
4. Make it obvious in every command which environment you're targeting

**Correct approach**:
```bash
# Explicit and obvious
terraform plan -var-file=terraform.tfvars.staging
terraform apply -var-file=terraform.tfvars.staging
terraform destroy -var-file=terraform.tfvars.staging

# Even better: Use Makefile targets
make safe-destroy ENVIRONMENT=staging VAR_FILE=terraform.tfvars.staging
```

**Real-world example**:
The dcg-gitea-stage incident happened partly because of this pitfall. The operator specified `-var-file=terraform.tfvars.prod`, but the backend was wrong. If the operator had also been relying on auto-loaded terraform.tfvars, it would have been even more confusing.

### Pitfall 2: Wrong gcloud Active Project

**Why it's dangerous**:
- GCloud project determines API authentication
- You might think you're operating on one project but actually on another
- Some operations will succeed, some will fail, creating confusion
- Error messages can be misleading

**How it causes incidents**:
```bash
# Last week: Worked on production
gcloud config set project cui-gitea-prod

# This week: Want to work on staging
# But forget to switch gcloud project
cd /home/notme/Desktop/code/DCG/gitea/terraform/gcp-gitea
terraform apply -var-file=terraform.tfvars.staging

# Terraform might use the wrong project for some operations
# Results in inconsistent state or unexpected errors
```

**How to check**:
```bash
# Check current project
gcloud config get-value project

# Expected output: dcg-gitea-stage (or whatever you intend)
```

**How to fix**:
```bash
# Set correct project
gcloud config set project dcg-gitea-stage

# Verify change
gcloud config get-value project
```

**How to avoid it**:
1. **Always verify gcloud project before operations**
2. Add to your muscle memory: `gcloud config get-value project`
3. Use `make show-environment` to see all contexts
4. Use `environment-selector.sh` to switch safely

**Pro tip**: Add to your shell prompt
```bash
# Add to ~/.bashrc
export PS1='[\u@\h \W $(gcloud config get-value project 2>/dev/null)]\$ '

# Your prompt will show: [user@hostname dir dcg-gitea-stage]$
```

### Pitfall 3: Multiple tfvars Files Confusion

**Why it's dangerous**:
- Multiple .tfvars files can exist in the same directory
- Terraform has a precedence order for loading them
- Easy to get confused about which values take priority
- Can lead to unexpected configuration

**Terraform variable loading order (lowest to highest priority)**:
1. Default values in .tf files
2. Environment variables (TF_VAR_*)
3. terraform.tfvars (auto-loaded)
4. terraform.tfvars.json (auto-loaded)
5. *.auto.tfvars (auto-loaded, alphabetically)
6. *.auto.tfvars.json (auto-loaded, alphabetically)
7. -var-file= parameters (in order specified)
8. -var= flags (in order specified)

**How it causes incidents**:
```bash
# You have multiple files
# terraform.tfvars (from last week - staging)
# terraform.tfvars.prod (for production)

# You think you're being explicit
terraform apply -var-file=terraform.tfvars.prod

# But terraform ALSO auto-loads terraform.tfvars
# If both files set project_id, prod wins (later in precedence)
# But if terraform.tfvars sets OTHER variables, those are still used!
# Results in mixed configuration: some staging, some prod
```

**How to avoid it**:
1. **Never create terraform.tfvars** (without environment suffix)
2. Don't use .auto.tfvars files (surprising auto-loading)
3. Don't use TF_VAR_ environment variables for project selection
4. Use only explicit -var-file with environment-suffixed files
5. Use `environment-selector.sh` to ensure clean state

**Best practice**:
```bash
# Only these files should exist
terraform.tfvars.dev
terraform.tfvars.staging
terraform.tfvars.prod
terraform.tfvars.example

# Always use explicit parameter
terraform apply -var-file=terraform.tfvars.staging

# Better: Use scripts that handle this correctly
./scripts/environment-selector.sh staging
```

### Pitfall 4: Skipping Validation "To Save Time"

**Why it's dangerous**:
- Validation takes 2 minutes
- Recovery from an incident takes 4-6 hours
- You might think "I'm just making a small change"
- Small changes can have big impacts if context is wrong

**The rationalization**:
- "I'm just running a plan, not apply"
- "I've done this a hundred times"
- "I'm in a hurry"
- "The validation script is slow"
- "I already checked the project"

**Why this thinking is wrong**:
- Plans can reveal misconfigurations that lead to apply mistakes
- Experience doesn't prevent context mismatches
- Being in a hurry is when mistakes happen most
- Validation script takes 2 minutes max
- Checking project is not enough (backend and state matter too)

**Real-world example**:
In the dcg-gitea-stage incident, the operator was experienced and had decommissioned environments before. But they skipped validation because they "knew what they were doing." The result: 6 hours of recovery time.

**How to avoid it**:
1. **Make validation non-negotiable** - Like a pilot's pre-flight checklist
2. Run validation even for "small" changes
3. Run validation even if you're "sure" everything is right
4. If you're in a hurry, validation is MORE important, not less
5. Use Makefile targets that include validation automatically

**Time investment**:
- Validation: 2 minutes
- Recovery from incident: 4-6 hours
- ROI: 120x-180x return on time investment

**Make validation a habit, not a choice.**

### Pitfall 5: Force Flags Without Understanding

**Why it's dangerous**:
- Force flags bypass safety checks
- Usually used when you're frustrated with errors
- Error messages are trying to protect you
- Forcing through them creates bigger problems

**Common force flags**:
```bash
# These should almost NEVER be used
terraform destroy -auto-approve
terraform apply -auto-approve
terraform init -reconfigure -force-copy
terraform apply -refresh=false
terraform apply -lock=false
```

**When people use force flags**:
- "I keep getting an error, I'll just force it"
- "The lock is stuck, I'll disable it"
- "The refresh is slow, I'll skip it"
- "I need this done quickly"

**Why this is dangerous**:
- Errors indicate real problems that need investigation
- Locks prevent concurrent operations that corrupt state
- Refresh ensures state matches reality
- Speed at the cost of safety causes incidents

**The only acceptable use of force flags**:
1. You fully understand why the safety check is failing
2. You've investigated and determined it's safe to bypass
3. You've consulted with a senior engineer
4. You've documented why you're using the flag

**How to avoid this pitfall**:
1. When you get an error, READ IT and understand it
2. Don't use force flags as a first response
3. Ask for help if you don't understand the error
4. Use proper procedures instead of forcing through problems

**Example of proper handling**:
```bash
# ❌ Wrong: See error, force through
terraform destroy -var-file=terraform.tfvars.staging
# Error: Backend configuration has changed
terraform init -reconfigure -force-copy  # Bad!

# ✅ Correct: Investigate error, use proper procedure
terraform destroy -var-file=terraform.tfvars.staging
# Error: Backend configuration has changed
# Investigation: Backend was changed to different environment
# Solution: Use environment-selector.sh to properly switch
./scripts/environment-selector.sh staging
# Now backend, gcloud, and variables all aligned safely
```

---

## Validation Checklist

This checklist should be printed and kept at your workstation. Use it before any significant infrastructure operation.

```
╔════════════════════════════════════════════════════════════════════╗
║                   INFRASTRUCTURE OPERATIONS CHECKLIST              ║
╠════════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  BEFORE ANY INFRASTRUCTURE OPERATION                               ║
║                                                                    ║
║  □ 1. I have read SAFE_OPERATIONS_GUIDE.md                        ║
║                                                                    ║
║  □ 2. I have identified the target environment:                   ║
║        Environment: _______________ (dev/staging/prod)            ║
║        Project ID: ________________________________               ║
║                                                                    ║
║  □ 3. I have verified the gcloud active project:                  ║
║        Command: gcloud config get-value project                   ║
║        Output: ____________________________________               ║
║        Matches target? YES □  NO □                                ║
║                                                                    ║
║  □ 4. I have run the validation script:                           ║
║        Command: ./scripts/terraform-project-validator.sh          ║
║        Result: PASSED □  FAILED □                                 ║
║        If FAILED, I have resolved the issue before continuing     ║
║                                                                    ║
║  □ 5. I have verified all three contexts align:                   ║
║        Command: make show-environment                             ║
║        GCloud project matches: YES □  NO □                        ║
║        Backend bucket matches: YES □  NO □                        ║
║        State resources match: YES □  NO □                         ║
║                                                                    ║
║  □ 6. I am using explicit -var-file parameter:                    ║
║        File: terraform.tfvars.__________ (environment suffix)     ║
║        NO auto-loaded terraform.tfvars exists: YES □  NO □        ║
║                                                                    ║
║  BEFORE ANY DESTROY OPERATION (Additional checks)                 ║
║                                                                    ║
║  □ 7. I have run the pre-destroy validation:                      ║
║        Command: ./scripts/pre-destroy-validator.sh                ║
║        Result: PASSED □  FAILED □                                 ║
║                                                                    ║
║  □ 8. I have reviewed the destroy plan:                           ║
║        Resource count: _______ resources to destroy               ║
║        Expected range: _______ to _______                         ║
║        Within range? YES □  NO □                                  ║
║                                                                    ║
║  □ 9. I have verified resource names in the destroy plan:         ║
║        All resource names contain correct project: YES □  NO □    ║
║        NO wrong project names found: YES □  NO □                  ║
║        Command: terraform show destroy.tfplan | grep project      ║
║                                                                    ║
║  □ 10. I understand the impact:                                   ║
║         Number of resources to destroy: _______                   ║
║         Services affected: _______________________________        ║
║         Data to be lost: __________________________________       ║
║         Backup exists: YES □  NO □  N/A □                         ║
║                                                                    ║
║  □ 11. I have approval (if required):                             ║
║         Approval required? YES □  NO □                            ║
║         Approval obtained from: _______________________           ║
║         Ticket/CR number: _____________________________           ║
║                                                                    ║
║  □ 12. I know how to recover if something goes wrong:             ║
║         Rollback procedure: _____________________________         ║
║         Recovery time estimate: _______________ hours             ║
║         Senior engineer contact: ________________________         ║
║                                                                    ║
║  IF ANY CHECKBOX IS UNCHECKED, DO NOT PROCEED                     ║
║  IF ANY ANSWER IS "NO" OR UNEXPECTED, STOP AND INVESTIGATE        ║
║  IF IN DOUBT, ASK A SENIOR ENGINEER                               ║
║                                                                    ║
║  Operator: ________________________  Date: ___________________   ║
║  Reviewer (if required): ____________  Date: _________________   ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝
```

**How to use this checklist**:

1. **Print it** and keep it at your desk
2. **Use it every time** you perform infrastructure operations
3. **Fill it out honestly** - don't skip steps
4. **If any check fails**, stop and investigate before continuing
5. **Keep completed checklists** as evidence for compliance audits

**Digital version**:
A digital version is available at `/home/notme/Desktop/code/DCG/gitea/docs/OPERATIONS_CHECKLIST.md`

---

## Emergency Procedures

Despite all precautions, incidents can still occur. If you realize you've made a mistake or are performing an operation on the wrong environment, follow these procedures immediately.

### Scenario 1: Realized Mid-Destruction You Targeted Wrong Project

**Immediate actions (within 30 seconds)**:

1. **PRESS CTRL+C IMMEDIATELY**
   - This attempts to interrupt Terraform
   - May not stop all deletions in progress
   - Some resources may already be destroyed
   - But will stop future deletions

2. **Do NOT press CTRL+C multiple times**
   - A single CTRL+C attempts graceful shutdown
   - Multiple CTRL+C can corrupt state
   - Wait 10 seconds for Terraform to respond

3. **Note the time**
   - Write down the exact time destruction started
   - This is critical for incident timeline

**Next steps (within 5 minutes)**:

1. **Assess what's been destroyed so far**
   ```bash
   # List remaining resources in state
   terraform state list > /tmp/remaining_resources_$(date +%Y%m%d_%H%M%S).txt

   # Count remaining vs. expected
   echo "Remaining resources: $(terraform state list | wc -l)"

   # Check what's actually in GCP
   gcloud compute instances list --project=<wrong-project>
   gcloud compute disks list --project=<wrong-project>
   gcloud sql instances list --project=<wrong-project>
   ```

2. **DO NOT run any more Terraform commands**
   - Don't try to "fix" it with terraform apply
   - Don't run terraform destroy again
   - Don't run terraform refresh
   - State may be in inconsistent state

3. **Declare an incident**
   ```bash
   # Send immediate notification
   echo "INCIDENT: Accidental destruction of <project-id>" | \
     mail -s "P1: GCP Resource Destruction" team@dcg.example.com

   # Or use your team's incident notification system
   # Slack: #incidents channel
   # PagerDuty: Trigger P1 alert
   ```

4. **Lock the state file**
   ```bash
   # Prevent others from making concurrent changes
   BACKEND_BUCKET=$(grep bucket terraform/gcp-gitea/backend.tf | awk -F'"' '{print $2}')
   gsutil -m acl ch -u operator@email.com:R gs://${BACKEND_BUCKET}/*
   ```

**Recovery steps (first hour)**:

1. **Contact senior engineer immediately**
   - Explain what happened
   - Provide timeline
   - Share remaining_resources.txt file
   - Don't try to fix alone

2. **Check for evidence bucket**
   ```bash
   # Evidence bucket usually has 7-year retention
   gsutil ls gs://<project>-*-evidence-*

   # If exists, it should be protected
   # This is good news for recovery
   ```

3. **Retrieve last known good state**
   ```bash
   # State bucket should have versioning enabled
   BACKEND_BUCKET=$(grep bucket terraform/gcp-gitea/backend.tf | awk -F'"' '{print $2}')

   # List state versions
   gsutil ls -a gs://${BACKEND_BUCKET}/terraform/state/

   # Copy last known good state
   gsutil cp gs://${BACKEND_BUCKET}/terraform/state/default.tfstate#<version> \
     /tmp/last_good_state_$(date +%Y%m%d_%H%M%S).tfstate
   ```

4. **Follow GCP_DISASTER_RECOVERY.md**
   - Located at `/home/notme/Desktop/code/DCG/gitea/docs/GCP_DISASTER_RECOVERY.md`
   - Contains detailed recovery procedures
   - Includes terraform import commands
   - Covers data restoration from backups

**What NOT to do**:

- ❌ Don't panic and make more changes
- ❌ Don't try to hide the incident
- ❌ Don't attempt recovery without senior engineer guidance
- ❌ Don't run terraform commands on the affected state
- ❌ Don't touch the working environment while investigating

### Scenario 2: Wrong Project Destroyed, Discovered After Completion

**Immediate actions**:

1. **Acknowledge the situation**
   ```bash
   # Confirm destruction is complete
   terraform state list  # Should be empty or minimal

   # Check GCP
   gcloud compute instances list --project=<wrong-project>  # Should be empty
   ```

2. **Declare P1 incident**
   - Full resource destruction
   - Immediate team notification
   - Management notification
   - Begin incident timeline documentation

3. **Preserve evidence**
   ```bash
   # Save terminal history
   history > /tmp/incident_history_$(date +%Y%m%d_%H%M%S).txt

   # Save Terraform logs
   cp -r .terraform/ /tmp/incident_terraform_backup/

   # Save state versions
   BACKEND_BUCKET=$(grep bucket terraform/gcp-gitea/backend.tf | awk -F'"' '{print $2}')
   mkdir -p /tmp/incident_state_backup/
   gsutil -m cp -r gs://${BACKEND_BUCKET}/* /tmp/incident_state_backup/

   # Save backend config
   cp terraform/gcp-gitea/backend.tf /tmp/incident_backend_$(date +%Y%m%d_%H%M%S).tf
   ```

4. **Begin recovery**
   - Follow GCP_DISASTER_RECOVERY.md procedures
   - Senior engineer leads recovery effort
   - Document every step
   - Estimated time: 4-6 hours for full recovery

### Scenario 3: State Corruption Detected

**Symptoms**:
- Terraform shows resources that don't exist in GCP
- Terraform doesn't show resources that DO exist in GCP
- Error: "state lock could not be obtained"
- Error: "state file appears to be corrupted"

**Immediate actions**:

1. **Stop all operations**
   - Don't run any terraform commands
   - Notify team to stop operations on this environment
   - Lock state file to prevent concurrent access

2. **Retrieve state backup**
   ```bash
   # State bucket has versioning
   BACKEND_BUCKET=$(grep bucket terraform/gcp-gitea/backend.tf | awk -F'"' '{print $2}')

   # List versions
   gsutil ls -a gs://${BACKEND_BUCKET}/terraform/state/default.tfstate

   # Download last 3 versions
   for i in 1 2 3; do
     gsutil cp gs://${BACKEND_BUCKET}/terraform/state/default.tfstate#<version-$i> \
       /tmp/state_backup_version_$i.tfstate
   done
   ```

3. **Validate backup states**
   ```bash
   # Check each backup state file
   for i in 1 2 3; do
     echo "=== Checking version $i ==="
     terraform state list -state=/tmp/state_backup_version_$i.tfstate | wc -l
   done

   # Compare with GCP reality
   gcloud compute instances list --project=<project> | wc -l
   ```

4. **Contact senior engineer**
   - State recovery requires expertise
   - May need manual state reconstruction
   - Could require terraform import commands

### Emergency Contacts

**During business hours (8am-6pm Pacific)**:
- Team Lead: [Name] - Slack @teamlead
- Senior DevOps: [Name] - Slack @seniordevops
- Platform Engineer: [Name] - Slack @platform

**After hours / Weekends**:
- On-call rotation: PagerDuty escalation
- Emergency hotline: [Phone number]

**For major incidents (P0/P1)**:
- Incident Commander: Auto-assigned via PagerDuty
- Executive notification: Automatic for P0, manual for P1
- Customer notification: Required within 1 hour if customer-impacting

### Post-Incident Procedures

After any incident, no matter how minor:

1. **Create incident timeline**
   - What happened, when, and why
   - Use template at `docs/templates/INCIDENT_REPORT_TEMPLATE.md`

2. **Root cause analysis**
   - Technical root cause
   - Process failure
   - Why did safeguards not prevent it?

3. **Lessons learned document**
   - What we learned
   - What we'll change
   - How we'll prevent recurrence

4. **Update procedures**
   - Improve documentation
   - Enhance validation scripts
   - Add new safeguards

5. **Team training**
   - Share lessons learned with team
   - Update this training document
   - Conduct incident review meeting

**Remember: The goal is not to assign blame, but to prevent recurrence.**

---

## Knowledge Check Quiz

Complete this quiz to verify your understanding of the training material. You must score 90% or higher (9/10 correct) to pass.

### Question 1
**True or False**: If your gcloud project is set to the correct project, you are safe to run terraform operations without further validation.

<details>
<summary>Click to reveal answer</summary>

**Answer: FALSE**

**Explanation**: GCloud project is only ONE of three contexts that must align. You must also verify:
1. Terraform backend configuration (which state bucket)
2. Terraform state resources (which resources are in state)

Even if gcloud is correct, if your backend points to a different environment's state bucket, you will operate on the wrong environment. This is exactly what happened in the dcg-gitea-stage incident.
</details>

### Question 2
**Multiple Choice**: Which command should you ALWAYS use before performing a terraform destroy operation?

A) `gcloud config get-value project`
B) `terraform validate`
C) `./scripts/pre-destroy-validator.sh`
D) `terraform plan -destroy`

<details>
<summary>Click to reveal answer</summary>

**Answer: C**

**Explanation**: While A, B, and D are all important checks, `./scripts/pre-destroy-validator.sh` is the mandatory script before destruction. It performs ALL the necessary checks including:
- Validates gcloud project
- Verifies terraform backend
- Checks state resources
- Generates and reviews destroy plan
- Requires explicit confirmation
- Creates evidence snapshot

It encompasses all other checks plus additional safety measures.
</details>

### Question 3
**True or False**: Using `terraform.tfvars` (without an environment suffix) is acceptable as long as you know which project is configured in it.

<details>
<summary>Click to reveal answer</summary>

**Answer: FALSE**

**Explanation**: `terraform.tfvars` (without suffix) should NEVER be used because:
1. It's auto-loaded without you specifying it explicitly
2. It's ambiguous which environment it represents
3. You can forget which project it's configured for
4. No visual indication in your command which environment is active
5. Can be left over from previous work on different environment

Always use environment-suffixed files like `terraform.tfvars.staging` with explicit `-var-file` parameter.
</details>

### Question 4
**Scenario**: You run a destroy plan and see resource names like `dcg-gitea-stage-staging-vm` but you intended to destroy `cui-gitea-prod`. What should you do?

A) Continue with the destroy - the resource names are probably just outdated
B) Add `-var-file=terraform.tfvars.prod` to override the names
C) STOP immediately and investigate why the names don't match your intent
D) Run `terraform refresh` to update the resource names

<details>
<summary>Click to reveal answer</summary>

**Answer: C**

**Explanation**: Resource names in a plan showing a different environment than you intended is a CRITICAL RED FLAG. This indicates your Terraform backend is pointing to the wrong environment's state. This is exactly what happened in the dcg-gitea-stage incident - the operator saw `dcg-gitea-stage` but rationalized it away instead of investigating.

NEVER rationalize unexpected resource names. ALWAYS stop and investigate. Resource names in plans are not "outdated" - they reflect the actual state bucket you're operating on.
</details>

### Question 5
**Multiple Choice**: The three contexts that must align for safe Terraform operations are:

A) Terraform version, Terragrunt version, Provider version
B) GCloud project, Terraform backend, Terraform variables
C) Working directory, Variable file, State file
D) Project ID, Region, Zone

<details>
<summary>Click to reveal answer</summary>

**Answer: B**

**Explanation**: The three critical contexts are:
1. **GCloud Configuration** - Authentication and API calls
2. **Terraform Backend** - Where state is stored (determines which environment)
3. **Terraform Variables** - Configuration values for resources

All three must point to the same environment. If any one is misaligned, you will operate on the wrong environment or create inconsistent configuration.
</details>

### Question 6
**True or False**: Skipping validation to save time is acceptable for small changes or when you're experienced with the system.

<details>
<summary>Click to reveal answer</summary>

**Answer: FALSE**

**Explanation**:
- Validation takes 2 minutes
- Recovery from an incident takes 4-6 hours
- "Small" changes can have big impacts if context is wrong
- Experience doesn't prevent context mismatches
- Being in a hurry is when mistakes happen MOST

The dcg-gitea-stage incident was caused by an experienced operator who skipped validation. Make validation non-negotiable, like a pilot's pre-flight checklist.
</details>

### Question 7
**Scenario**: You're halfway through a terraform destroy operation when you realize you're destroying the wrong environment. What should you do?

A) Let it finish, then restore from backup
B) Press CTRL+C immediately, once
C) Press CTRL+C repeatedly until it stops
D) Run `terraform apply` in another terminal to restore resources

<details>
<summary>Click to reveal answer</summary>

**Answer: B**

**Explanation**:
- Press CTRL+C **once** immediately
- A single CTRL+C attempts graceful shutdown
- Multiple CTRL+C can corrupt state
- Wait 10 seconds for Terraform to respond
- Do NOT run any other terraform commands
- Some resources may already be destroyed, but you'll stop future deletions
- Declare incident and follow emergency procedures

Option A wastes time and destroys more resources. Option C risks state corruption. Option D will cause state conflicts.
</details>

### Question 8
**Multiple Choice**: When should you use the `-auto-approve` flag with terraform destroy?

A) When you're certain you're in the correct environment
B) When you've run the validation scripts
C) When you're in a hurry
D) Almost never - only when you fully understand the risks and have senior approval

<details>
<summary>Click to reveal answer</summary>

**Answer: D**

**Explanation**: The `-auto-approve` flag bypasses the final confirmation prompt, which is a critical safety check. It should almost NEVER be used. Even if you:
- Are certain you're in the correct environment
- Have run validation scripts
- Have reviewed the plan

You should still review the resources being destroyed one final time before applying. The only acceptable use is in automated systems where:
- The destroy plan has been reviewed by a human
- The operation has been approved
- The risk is fully understood and accepted
- You have senior engineer approval

Never use it just to save time or skip the confirmation prompt.
</details>

### Question 9
**True or False**: The Terraform backend configuration in `backend.tf` determines which environment's state you're operating on, regardless of your gcloud project or variable file settings.

<details>
<summary>Click to reveal answer</summary>

**Answer: TRUE**

**Explanation**: This is the critical lesson from the dcg-gitea-stage incident. The backend configuration is the **SOURCE OF TRUTH** for which environment you're operating on.

Even if:
- Your gcloud project is set to `cui-gitea-prod`
- Your variable file specifies `project_id = "cui-gitea-prod"`
- You have authorization to modify cui-gitea-prod

If your `backend.tf` specifies the dcg-gitea-stage state bucket, you will operate on dcg-gitea-stage resources.

This is why backend validation is MANDATORY before operations.
</details>

### Question 10
**Scenario**: You need to switch from working on staging to working on production. What is the RECOMMENDED way to do this safely?

A) Just change the -var-file parameter to terraform.tfvars.prod
B) Run `gcloud config set project cui-gitea-prod` then proceed
C) Edit backend.tf to point to the production state bucket
D) Use `./scripts/environment-selector.sh prod`

<details>
<summary>Click to reveal answer</summary>

**Answer: D**

**Explanation**: The `environment-selector.sh` script is specifically designed for safe environment switching. It:
1. Prompts for confirmation of target environment
2. Sets gcloud project
3. Verifies gcloud project change
4. Backs up current backend.tf
5. Updates backend.tf with new state bucket
6. Runs `terraform init -reconfigure`
7. Validates state matches new environment
8. Displays summary of new context

Options A, B, and C only update ONE of the three contexts, leaving you vulnerable to operating on the wrong environment. Option D ensures all three contexts are properly aligned.

This is the MANDATORY way to switch environments.
</details>

---

## Quiz Scoring

**Count your correct answers:**

- **10/10**: Perfect score! You fully understand the safety procedures.
- **9/10**: Pass - You understand the core concepts. Review the question you missed.
- **8/10 or below**: Did not pass - Please re-read the training material and retake the quiz.

**Passing requirement**: 9/10 or higher (90%)

If you did not pass, please:
1. Review the training material again
2. Read the explanations for questions you missed
3. Ask questions if anything is unclear
4. Retake the quiz

---

## Certification

### Training Completion Statement

I certify that I have:

1. Read and understood this entire Safety Training Guide
2. Reviewed the Critical Incident Case Study and understand how it happened
3. Learned about all safety tools and documentation available
4. Memorized the mandatory procedures
5. Studied the common pitfalls and how to avoid them
6. Reviewed the validation checklist
7. Understood the emergency procedures
8. Completed the knowledge check quiz with a score of 90% or higher

I understand that:

- Infrastructure operations are powerful and mistakes can be costly
- I must follow all mandatory procedures without exception
- Validation scripts exist for my safety and must not be skipped
- I should ask questions when uncertain rather than proceed with doubt
- Speed is never more important than safety
- I am responsible for verifying my context before all operations

I commit to:

- Always verifying all three contexts (gcloud, backend, variables) before operations
- Using explicit -var-file parameters, never relying on auto-loading
- Running validation scripts before destructive operations
- Reviewing all destroy plans thoroughly before applying
- Asking for help when anything is unclear or unexpected
- Following emergency procedures if an incident occurs
- Learning from incidents and helping improve our procedures

---

**Trainee Information:**

Name: ________________________________________________

Date: ________________________________________________

Quiz Score: _______ / 10 (Must be 9 or higher)

Email: ________________________________________________

Team: ________________________________________________

**Trainee Signature:**

________________________________________________


---

**Manager Approval:**

I confirm that the above team member has:
- Completed this safety training
- Achieved a passing score on the knowledge check quiz
- Demonstrated understanding in our discussion
- Is authorized to perform infrastructure operations

Manager Name: ________________________________________________

Manager Signature: ________________________________________________

Date: ________________________________________________

---

**Training Record:**

This certification should be:
1. Signed by trainee and manager
2. Scanned or photographed
3. Uploaded to team documentation system
4. Recorded in HR training records
5. Kept on file for compliance audits

**Validity**: This certification is valid for 12 months. Annual refresher training is required.

**Next Review Date**: ________________________________________________

---

## Appendix: Quick Reference Card

Print this card and keep it at your workstation for quick reference.

```
╔══════════════════════════════════════════════════════════════════╗
║                    QUICK REFERENCE CARD                          ║
║              Infrastructure Operations Safety                    ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  BEFORE ANY OPERATION:                                           ║
║                                                                  ║
║  1. Verify gcloud project:                                       ║
║     gcloud config get-value project                              ║
║                                                                  ║
║  2. Check all contexts:                                          ║
║     make show-environment                                        ║
║                                                                  ║
║  3. Run validation:                                              ║
║     ./scripts/terraform-project-validator.sh                     ║
║                                                                  ║
║  BEFORE ANY DESTROY:                                             ║
║                                                                  ║
║  1. Run pre-destroy validation:                                  ║
║     ./scripts/pre-destroy-validator.sh \                         ║
║       --project=<project-id> \                                   ║
║       --var-file=terraform.tfvars.<env>                          ║
║                                                                  ║
║  2. Review destroy plan:                                         ║
║     terraform show destroy.tfplan | less                         ║
║                                                                  ║
║  3. Verify resource names match intent                           ║
║                                                                  ║
║  SWITCHING ENVIRONMENTS:                                         ║
║                                                                  ║
║  Always use:                                                     ║
║     ./scripts/environment-selector.sh <env>                      ║
║                                                                  ║
║  EMERGENCY:                                                      ║
║                                                                  ║
║  Wrong environment being destroyed:                              ║
║     1. Press CTRL+C once immediately                             ║
║     2. Do NOT run more terraform commands                        ║
║     3. Declare incident                                          ║
║     4. Contact senior engineer                                   ║
║                                                                  ║
║  GOLDEN RULES:                                                   ║
║                                                                  ║
║  ✓ Always use explicit -var-file parameter                       ║
║  ✓ Never skip validation to "save time"                          ║
║  ✓ Stop and investigate unexpected output                        ║
║  ✓ Ask questions when uncertain                                  ║
║  ✓ Safety over speed, always                                     ║
║                                                                  ║
║  Emergency Contact: [FILL IN]                                    ║
║  Documentation: docs/SAFE_OPERATIONS_GUIDE.md                    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
```

---

**END OF SAFETY TRAINING GUIDE**

For questions or feedback on this training material, please contact the DevOps team or submit a pull request with suggested improvements.

**Remember**: Safety is everyone's responsibility. These procedures exist because incidents have happened before. Don't let history repeat itself.
