#!/bin/bash
# ==============================================================================
# GCP Gitea Safe Teardown Script
# CMMC Level 2 / NIST SP 800-171 Compliant
# ==============================================================================
#
# Usage: ./gcp-destroy.sh [options]
#   -p PROJECT_ID    GCP Project ID (required)
#   -e ENVIRONMENT   Environment: dev|staging|prod (required)
#   -r REGION        GCP Region (default: us-central1)
#   -V VAR_FILE      Terraform variable file (HIGHLY RECOMMENDED for safety)
#   -k               Keep evidence bucket after destruction
#   -b               Create final backup before destruction
#   -f               Force destroy without confirmation
#   -n               Dry run - show what would be destroyed
#   -s               Skip safety validation (NOT RECOMMENDED)
#   -v               Verbose output
#   -h               Show this help message
#
# Examples:
#   ./gcp-destroy.sh -p my-project -e dev -V terraform.tfvars.dev          # Standard teardown with explicit var file
#   ./gcp-destroy.sh -p my-project -e prod -V terraform.tfvars.prod -k -b  # Keep evidence, backup first
#   ./gcp-destroy.sh -p my-project -e staging -V terraform.tfvars.staging -n  # Dry run
#
# Exit Codes:
#   0 - Success
#   1 - Error
#   2 - Warning/Partial destruction
#
# CMMC Controls Addressed:
#   - AU.L2-3.3.8: Protection of Audit Information
#   - CM.L2-3.4.9: User-Installed Software
#   - MA.L2-3.7.5: Nonlocal Maintenance
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TERRAFORM_DIR="${PROJECT_ROOT}/terraform/gcp-gitea"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly EVIDENCE_DIR="${TERRAFORM_DIR}/evidence"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${LOG_DIR}/destroy_${TIMESTAMP}.log"
readonly AUDIT_LOG="${LOG_DIR}/environment-audit.log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Default values
ENVIRONMENT=""
PROJECT_ID=""
REGION="us-central1"
ZONE=""
VAR_FILE=""
KEEP_EVIDENCE=false
CREATE_BACKUP=false
FORCE_DESTROY=false
DRY_RUN=false
SKIP_VALIDATION=false
VERBOSE=false
CONFIRM_PROJECT=""
EXPECTED_COUNT_MIN=""
EXPECTED_COUNT_MAX=""
EXPECTED_COUNT_SET=false

# Destruction state
DESTROY_ID=""
DESTROY_START=""
DESTROY_END=""
DESTROY_STATUS="PENDING"
RESOURCES_DESTROYED=0

# ==============================================================================
# FUNCTIONS
# ==============================================================================

# Print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Log message
log() {
    local level=$1
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"

    echo "${message}" >> "${LOG_FILE}"

    case "${level}" in
        ERROR)
            print_color "${RED}" "✗ $*" >&2
            ;;
        WARNING)
            print_color "${YELLOW}" "⚠ $*"
            ;;
        SUCCESS)
            print_color "${GREEN}" "✓ $*"
            ;;
        INFO)
            print_color "${BLUE}" "ℹ $*"
            ;;
        DEBUG)
            if [[ "${VERBOSE}" == "true" ]]; then
                print_color "${PURPLE}" "→ $*"
            fi
            ;;
    esac
}

# Log to audit log
audit_log() {
    local action="$1"
    shift
    local details="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')

    mkdir -p "$(dirname "${AUDIT_LOG}")"

    printf '[%s] ACTION=%s USER=%s HOST=%s %s\n' \
        "${timestamp}" \
        "${action}" \
        "${USER:-unknown}" \
        "$(hostname)" \
        "${details}" >> "${AUDIT_LOG}"
}

# Show usage
show_help() {
    grep "^#" "$0" | head -31 | tail -29 | sed 's/^# //' | sed 's/^#//'
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -p*)
                PROJECT_ID="${1#-p}"
                shift
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -e*)
                ENVIRONMENT="${1#-e}"
                shift
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -r*)
                REGION="${1#-r}"
                shift
                ;;
            -V|--var-file)
                VAR_FILE="$2"
                shift 2
                ;;
            -V*)
                VAR_FILE="${1#-V}"
                shift
                ;;
            -k|--keep-evidence)
                KEEP_EVIDENCE=true
                shift
                ;;
            -b|--backup)
                CREATE_BACKUP=true
                shift
                ;;
            -f|--force)
                FORCE_DESTROY=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-validation)
                SKIP_VALIDATION=true
                log WARNING "Safety validation will be skipped - USE WITH EXTREME CAUTION"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --confirm-project=*)
                CONFIRM_PROJECT="${1#*=}"
                shift
                ;;
            --confirm-project)
                CONFIRM_PROJECT="$2"
                shift 2
                ;;
            -C*)
                CONFIRM_PROJECT="${1#-C}"
                shift
                ;;
            --expected-count=*)
                set_expected_count "${1#*=}"
                shift
                ;;
            --expected-count)
                set_expected_count "$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                log ERROR "Invalid option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

set_expected_count() {
    local value="$1"
    if [[ -z "${value}" ]]; then
        log ERROR "Expected count value cannot be empty"
        exit 1
    fi

    if [[ "${value}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        EXPECTED_COUNT_MIN="${BASH_REMATCH[1]}"
        EXPECTED_COUNT_MAX="${BASH_REMATCH[2]}"
    elif [[ "${value}" =~ ^[0-9]+$ ]]; then
        EXPECTED_COUNT_MIN="${value}"
        EXPECTED_COUNT_MAX="${value}"
    else
        log ERROR "Invalid --expected-count value: ${value}. Use MIN-MAX or a single integer."
        exit 1
    fi

    if (( EXPECTED_COUNT_MIN > EXPECTED_COUNT_MAX )); then
        log ERROR "--expected-count min must be <= max (${EXPECTED_COUNT_MIN}-${EXPECTED_COUNT_MAX})"
        exit 1
    fi

    EXPECTED_COUNT_SET=true
}

# Validate parameters
validate_params() {
    local errors=0

    if [[ -z "${PROJECT_ID}" ]]; then
        log ERROR "Project ID is required (-p)"
        ((errors++))
    fi

    if [[ -z "${ENVIRONMENT}" ]]; then
        log ERROR "Environment is required (-e)"
        ((errors++))
    fi

    if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
        log ERROR "Invalid environment: ${ENVIRONMENT}"
        ((errors++))
    fi

    if [[ -z "${VAR_FILE}" ]]; then
        log ERROR "Variable file is required (-V or --var-file)"
        ((errors++))
    else
        local var_file_path="${VAR_FILE}"
        if [[ ! -f "${var_file_path}" ]]; then
            local var_basename
            var_basename=$(basename "${VAR_FILE}")
            if [[ -f "${TERRAFORM_DIR}/${var_basename}" ]]; then
                var_file_path="${TERRAFORM_DIR}/${var_basename}"
            elif [[ -f "${var_basename}" ]]; then
                var_file_path="${var_basename}"
            else
                log ERROR "Variable file not found: ${VAR_FILE}"
                ((errors++))
            fi
        fi
    fi

    if [[ -z "${CONFIRM_PROJECT}" ]]; then
        log ERROR "--confirm-project=PROJECT_ID is required"
        ((errors++))
    elif [[ "${CONFIRM_PROJECT}" != "${PROJECT_ID}" ]]; then
        log ERROR "--confirm-project (${CONFIRM_PROJECT}) must match supplied project ID (${PROJECT_ID})"
        ((errors++))
    fi

    if [[ ${errors} -gt 0 ]]; then
        exit 1
    fi

    ZONE="${REGION}-a"
    DESTROY_ID="destroy_${ENVIRONMENT}_${TIMESTAMP}"
}

# Initialize
init_directories() {
    mkdir -p "${LOG_DIR}"
    mkdir -p "${EVIDENCE_DIR}"

    touch "${LOG_FILE}"

    log DEBUG "Initialized directories"
}

# Run safety validation checks
run_safety_validation() {
    if [[ "${SKIP_VALIDATION}" == "true" ]]; then
        log WARNING "⚠️  SAFETY VALIDATION SKIPPED - Proceeding without validation"
        log WARNING "⚠️  This significantly increases the risk of destroying the wrong project"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log INFO "Dry run mode - skipping safety validation"
        return 0
    fi

    print_color "${BLUE}" "
╔══════════════════════════════════════════════════════════════════╗
║                    SAFETY VALIDATION CHECKS                      ║
╚══════════════════════════════════════════════════════════════════╝
"

    local validation_failed=false

    # Phase 1: Project Validator
    log INFO "Phase 1: Running terraform-project-validator.sh..."

    local project_validator="${SCRIPT_DIR}/terraform-project-validator.sh"
    if [[ ! -x "${project_validator}" ]]; then
        log ERROR "Project validator script not found or not executable: ${project_validator}"
        validation_failed=true
    else
        local validator_args=(
            "--operation=destroy"
            "--project=${PROJECT_ID}"
            "--terraform-dir=${TERRAFORM_DIR}"
        )

        if [[ -n "${VAR_FILE}" ]]; then
            validator_args+=("--var-file=${VAR_FILE}")
        fi

        if [[ "${FORCE_DESTROY}" == "true" ]]; then
            validator_args+=("--non-interactive" "--confirm-destroy")
        fi

        if ${project_validator} "${validator_args[@]}" 2>&1 | tee -a "${LOG_FILE}"; then
            log SUCCESS "Project validation passed"
        else
            log ERROR "Project validation FAILED"
            validation_failed=true
        fi
    fi

    echo ""

    # Phase 2: Pre-Destroy Validator
    log INFO "Phase 2: Running pre-destroy-validator.sh..."

    local predestroy_validator="${SCRIPT_DIR}/pre-destroy-validator.sh"
    if [[ ! -x "${predestroy_validator}" ]]; then
        log ERROR "Pre-destroy validator script not found or not executable: ${predestroy_validator}"
        validation_failed=true
    else
        local destroy_validator_args=(
            "--project=${PROJECT_ID}"
            "--terraform-dir=${TERRAFORM_DIR}"
        )

        if [[ -n "${VAR_FILE}" ]]; then
            destroy_validator_args+=("--var-file=${VAR_FILE}")
        fi

        if [[ "${EXPECTED_COUNT_SET}" == "true" ]]; then
            destroy_validator_args+=("--expected-resources=${EXPECTED_COUNT_MIN}-${EXPECTED_COUNT_MAX}")
        elif [[ ${RESOURCES_DESTROYED} -gt 0 ]]; then
            local min_resources=$((RESOURCES_DESTROYED - 20))
            local max_resources=$((RESOURCES_DESTROYED + 20))
            destroy_validator_args+=("--expected-resources=${min_resources}-${max_resources}")
        fi

        # Add non-interactive flag if force destroy is enabled
        if [[ "${FORCE_DESTROY}" == "true" ]]; then
            destroy_validator_args+=("--non-interactive" "--confirm-destroy")
        fi

        if ${predestroy_validator} "${destroy_validator_args[@]}" 2>&1 | tee -a "${LOG_FILE}"; then
            log SUCCESS "Pre-destroy validation passed"
        else
            local exit_code=$?
            if [[ ${exit_code} -eq 3 ]]; then
                log WARNING "User cancelled operation during validation"
                exit 3
            else
                log ERROR "Pre-destroy validation FAILED"
                validation_failed=true
            fi
        fi
    fi

    echo ""

    # Final validation result
    if [[ "${validation_failed}" == "true" ]]; then
        print_color "${RED}" "
╔══════════════════════════════════════════════════════════════════╗
║               ❌ SAFETY VALIDATION FAILED ❌                      ║
╠══════════════════════════════════════════════════════════════════╣
║ One or more safety checks failed. DO NOT PROCEED!                ║
║                                                                   ║
║ Review the validation errors above and:                          ║
║   1. Verify you are targeting the correct project                ║
║   2. Check your variable files                                   ║
║   3. Ensure gcloud project context is correct                    ║
║   4. Review terraform state                                      ║
║                                                                   ║
║ See: ${SAFE_OPERATIONS_GUIDE}║
╚══════════════════════════════════════════════════════════════════╝
"
        log ERROR "Safety validation failed - destruction blocked"
        exit 1
    else
        print_color "${GREEN}" "
╔══════════════════════════════════════════════════════════════════╗
║               ✅ SAFETY VALIDATION PASSED ✅                      ║
╠══════════════════════════════════════════════════════════════════╣
║ All safety checks passed. Safe to proceed with destruction.      ║
║                                                                   ║
║ Project verified:     ${PROJECT_ID}
║ Terraform state:      Validated                                  ║
║ Destroy plan:         Analyzed and approved                      ║
╚══════════════════════════════════════════════════════════════════╝
"
        log SUCCESS "All safety validation checks passed"
    fi

    return 0
}

# Reference to safe operations guide
readonly SAFE_OPERATIONS_GUIDE="${PROJECT_ROOT}/docs/SAFE_OPERATIONS_GUIDE.md"

# Check current infrastructure
check_infrastructure() {
    log INFO "Checking current infrastructure..."

    cd "${TERRAFORM_DIR}"

    if [[ ! -f "terraform.tfstate" ]]; then
        log WARNING "No Terraform state file found"
        return 1
    fi

    # List resources to be destroyed
    log INFO "Resources that will be destroyed:"

    if command -v terraform &>/dev/null; then
        terraform show -json 2>/dev/null | \
            jq -r '.values.root_module.resources[] | "\(.type).\(.name)"' | \
            while read -r resource; do
                log DEBUG "  - ${resource}"
                ((RESOURCES_DESTROYED++))
            done || true
    fi

    # Get bucket names
    EVIDENCE_BUCKET="gitea-${ENVIRONMENT}-evidence-${PROJECT_ID}"
    BACKUP_BUCKET="gitea-${ENVIRONMENT}-backup-${PROJECT_ID}"
    LOGS_BUCKET="gitea-${ENVIRONMENT}-logs-${PROJECT_ID}"

    log SUCCESS "Infrastructure check completed"
}

# Create final backup
create_final_backup() {
    if [[ "${CREATE_BACKUP}" != "true" ]]; then
        log INFO "Skipping final backup (use -b to enable)"
        return 0
    fi

    log INFO "Creating final backup before destruction..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would create final backup"
        return 0
    fi

    # Run backup script
    if [[ -x "${SCRIPT_DIR}/gcp-backup.sh" ]]; then
        "${SCRIPT_DIR}/gcp-backup.sh" \
            -p "${PROJECT_ID}" \
            -e "${ENVIRONMENT}" \
            -r "${REGION}" \
            -t full \
            -f || {
                log ERROR "Final backup failed"

                if [[ "${FORCE_DESTROY}" != "true" ]]; then
                    read -p "Continue without backup? (y/n): " -r
                    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
                        log WARNING "Destruction cancelled"
                        exit 0
                    fi
                fi
            }
    else
        log WARNING "Backup script not found"
    fi
}

# Export evidence and logs
export_evidence() {
    log INFO "Exporting evidence and logs..."

    local export_dir="${PROJECT_ROOT}/exports/${ENVIRONMENT}_${TIMESTAMP}"
    mkdir -p "${export_dir}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would export evidence to: ${export_dir}"
        return 0
    fi

    # Download evidence from GCS
    if gsutil ls -b "gs://${EVIDENCE_BUCKET}" &>/dev/null; then
        log INFO "Downloading evidence from GCS..."
        gsutil -m cp -r "gs://${EVIDENCE_BUCKET}/*" "${export_dir}/evidence/" 2>/dev/null || \
            log WARNING "Some evidence files could not be downloaded"
    fi

    # Download logs from GCS
    if gsutil ls -b "gs://${LOGS_BUCKET}" &>/dev/null; then
        log INFO "Downloading logs from GCS..."
        gsutil -m cp -r "gs://${LOGS_BUCKET}/*" "${export_dir}/logs/" 2>/dev/null || \
            log WARNING "Some log files could not be downloaded"
    fi

    # Export Terraform state
    if [[ -f "${TERRAFORM_DIR}/terraform.tfstate" ]]; then
        cp "${TERRAFORM_DIR}/terraform.tfstate" "${export_dir}/terraform_final.tfstate"
        log SUCCESS "Terraform state exported"
    fi

    # Create destruction manifest
    cat > "${export_dir}/destruction_manifest.json" <<EOF
{
  "destroy_id": "${DESTROY_ID}",
  "timestamp": "$(date -Iseconds)",
  "environment": "${ENVIRONMENT}",
  "project_id": "${PROJECT_ID}",
  "resources_destroyed": ${RESOURCES_DESTROYED},
  "evidence_kept": ${KEEP_EVIDENCE},
  "final_backup_created": ${CREATE_BACKUP},
  "operator": {
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "gcp_account": "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
  },
  "compliance": {
    "framework": "CMMC Level 2",
    "controls": ["AU.L2-3.3.8", "CM.L2-3.4.9", "MA.L2-3.7.5"]
  }
}
EOF

    log SUCCESS "Evidence exported to: ${export_dir}"
}

# Confirm destruction
confirm_destruction() {
    if [[ "${FORCE_DESTROY}" == "true" ]]; then
        log INFO "Force destroy enabled, skipping confirmation"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log INFO "Dry run mode, skipping confirmation"
        return 0
    fi

    local expected_text="Not set"
    if [[ "${EXPECTED_COUNT_SET}" == "true" ]]; then
        if [[ "${EXPECTED_COUNT_MIN}" == "${EXPECTED_COUNT_MAX}" ]]; then
            expected_text="${EXPECTED_COUNT_MIN}"
        else
            expected_text="${EXPECTED_COUNT_MIN}-${EXPECTED_COUNT_MAX}"
        fi
    fi

    print_color "${RED}" "
╔══════════════════════════════════════════════════════════════════╗
║                      ⚠⚠⚠ DANGER ZONE ⚠⚠⚠                        ║
╠══════════════════════════════════════════════════════════════════╣
║ This will PERMANENTLY DESTROY all infrastructure!                ║
║                                                                   ║
║ Environment:      ${ENVIRONMENT}
║ Project:          ${PROJECT_ID}
║ Resources:        ${RESOURCES_DESTROYED} resources will be destroyed
║ Expected Count:   ${expected_text}
║ Keep Evidence:    $(if [[ "${KEEP_EVIDENCE}" == "true" ]]; then echo "YES"; else echo "NO"; fi)
║ Final Backup:     $(if [[ "${CREATE_BACKUP}" == "true" ]]; then echo "YES"; else echo "NO"; fi)
╚══════════════════════════════════════════════════════════════════╝
"

    # Extra confirmation for production
    if [[ "${ENVIRONMENT}" == "prod" ]]; then
        print_color "${RED}" "
⚠⚠⚠ PRODUCTION ENVIRONMENT DETECTED ⚠⚠⚠

This is a PRODUCTION environment. Destroying it will cause immediate
service disruption and potential data loss.
"

        read -p "Type the environment name '${ENVIRONMENT}' to confirm: " -r
        if [[ "${REPLY}" != "${ENVIRONMENT}" ]]; then
            log WARNING "Environment name mismatch. Destruction cancelled"
            exit 0
        fi
    fi

    read -p "Type the project ID '${PROJECT_ID}' to confirm: " -r confirm_project
    if [[ "${confirm_project}" != "${PROJECT_ID}" ]]; then
        log WARNING "Project confirmation mismatch. Expected ${PROJECT_ID}, got ${confirm_project:-<empty>}"
        exit 0
    fi

    read -p "Are you absolutely sure? Type 'destroy' to confirm: " -r confirm_word

    if [[ "${confirm_word}" != "destroy" ]]; then
        log WARNING "Destruction cancelled by user"
        exit 0
    fi

    if [[ "${ENVIRONMENT}" == "prod" ]]; then
        print_color "${YELLOW}" "
Final abort window: you have 10 seconds to cancel (Ctrl+C to abort)."
        for ((i=10; i>0; i--)); do
            printf "\rContinuing in %2d seconds..." "${i}"
            sleep 1
        done
        printf "\rContinuing now...           \n"
    fi
}

# Terraform destroy
terraform_destroy() {
    log INFO "Running Terraform destroy..."

    cd "${TERRAFORM_DIR}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would run: terraform destroy"

        # Show what would be destroyed
        terraform plan -destroy 2>&1 | tee -a "${LOG_FILE}" || true

        return 0
    fi

    # Handle evidence bucket specially
    local extra_args=""
    if [[ "${KEEP_EVIDENCE}" == "true" ]]; then
        log INFO "Evidence bucket will be preserved"
        extra_args="-target=google_storage_bucket.evidence"

        # First, remove evidence bucket from state to preserve it
        terraform state rm google_storage_bucket.evidence 2>/dev/null || true
    fi

    # Build terraform destroy command with explicit var-file if specified
    local destroy_cmd="terraform destroy -auto-approve"

    if [[ -n "${VAR_FILE}" ]]; then
        local destroy_var_file="${VAR_FILE}"
        if [[ ! -f "${destroy_var_file}" ]]; then
            local destroy_var_basename
            destroy_var_basename=$(basename "${VAR_FILE}")
            if [[ -f "${destroy_var_basename}" ]]; then
                destroy_var_file="${destroy_var_basename}"
            fi
        fi

        destroy_cmd="${destroy_cmd} -var-file=${destroy_var_file}"
        log INFO "Using explicit variable file: ${destroy_var_file}"
    else
        log WARNING "No var-file specified - terraform will auto-load terraform.tfvars"
    fi

    if [[ -n "${extra_args}" ]]; then
        destroy_cmd="${destroy_cmd} ${extra_args}"
    fi

    log INFO "Executing: ${destroy_cmd}"

    # Run destroy
    if ${destroy_cmd} 2>&1 | tee -a "${LOG_FILE}"; then
        log SUCCESS "Terraform destroy completed"
        DESTROY_STATUS="SUCCESS"
    else
        log ERROR "Terraform destroy failed"
        DESTROY_STATUS="FAILED"
        return 1
    fi
}

# Clean up local files
cleanup_local() {
    log INFO "Cleaning up local files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would clean up local Terraform files"
        return 0
    fi

    cd "${TERRAFORM_DIR}"

    # Backup state files before deletion
    if [[ -f "terraform.tfstate" ]]; then
        cp terraform.tfstate "terraform.tfstate.destroyed.${TIMESTAMP}"
        log DEBUG "State file backed up"
    fi

    # Remove Terraform files
    rm -f terraform.tfstate terraform.tfstate.backup
    rm -rf .terraform/
    rm -f .terraform.lock.hcl
    rm -f tfplan

    # Keep terraform.tfvars for reference
    if [[ -f "terraform.tfvars" ]]; then
        mv terraform.tfvars "terraform.tfvars.destroyed.${TIMESTAMP}"
    fi

    log SUCCESS "Local files cleaned up"
}

# Generate decommissioning evidence
generate_evidence() {
    log INFO "Generating decommissioning evidence..."

    local evidence_file="${EVIDENCE_DIR}/decommission_${TIMESTAMP}.json"

    DESTROY_END=$(date -Iseconds)

    cat > "${evidence_file}" <<EOF
{
  "decommission_id": "${DESTROY_ID}",
  "timestamp": "$(date -Iseconds)",
  "status": "${DESTROY_STATUS}",
  "environment": "${ENVIRONMENT}",
  "project_id": "${PROJECT_ID}",
  "resources_destroyed": ${RESOURCES_DESTROYED},
  "destroy_start": "${DESTROY_START}",
  "destroy_end": "${DESTROY_END}",
  "duration_seconds": $(($(date +%s) - $(date -d "${DESTROY_START}" +%s))),
  "evidence_preserved": ${KEEP_EVIDENCE},
  "final_backup_created": ${CREATE_BACKUP},
  "buckets": {
    "evidence": "${EVIDENCE_BUCKET}",
    "backup": "${BACKUP_BUCKET}",
    "logs": "${LOGS_BUCKET}"
  },
  "operator": {
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "gcp_account": "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')",
    "ip_address": "$(curl -s ifconfig.me || echo 'unknown')"
  },
  "git_info": {
    "commit": "$(git -C '${PROJECT_ROOT}' rev-parse HEAD 2>/dev/null || echo 'N/A')",
    "branch": "$(git -C '${PROJECT_ROOT}' rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')"
  },
  "compliance": {
    "framework": "CMMC Level 2",
    "standards": ["NIST SP 800-171 Rev. 2", "NIST SP 800-218"],
    "controls": ["AU.L2-3.3.8", "CM.L2-3.4.9", "MA.L2-3.7.5"],
    "retention_requirements": "Evidence retained for 7 years per CMMC requirements"
  },
  "verification": {
    "resources_remaining": "$(terraform show 2>/dev/null | grep resource | wc -l || echo '0')",
    "state_cleaned": $(if [[ -f "${TERRAFORM_DIR}/terraform.tfstate" ]]; then echo "false"; else echo "true"; fi)
  }
}
EOF

    log SUCCESS "Decommissioning evidence generated: ${evidence_file}"

    # Upload to evidence bucket if it still exists
    if [[ "${KEEP_EVIDENCE}" == "true" ]] && gsutil ls -b "gs://${EVIDENCE_BUCKET}" &>/dev/null; then
        gsutil cp "${evidence_file}" "gs://${EVIDENCE_BUCKET}/decommissioning/"
        log SUCCESS "Evidence uploaded to preserved bucket"
    fi
}

# Final report
generate_report() {
    local report_file="${LOG_DIR}/decommission_report_${TIMESTAMP}.txt"

    cat > "${report_file}" <<EOF
================================================================================
                        DECOMMISSIONING REPORT
================================================================================

Decommission ID:    ${DESTROY_ID}
Date:               $(date)
Status:             ${DESTROY_STATUS}

ENVIRONMENT
-----------
Name:               ${ENVIRONMENT}
Project:            ${PROJECT_ID}
Region:             ${REGION}

DESTRUCTION SUMMARY
-------------------
Resources Destroyed: ${RESOURCES_DESTROYED}
Evidence Preserved:  $(if [[ "${KEEP_EVIDENCE}" == "true" ]]; then echo "YES"; else echo "NO"; fi)
Final Backup:        $(if [[ "${CREATE_BACKUP}" == "true" ]]; then echo "YES"; else echo "NO"; fi)

TIMING
------
Start:              ${DESTROY_START}
End:                ${DESTROY_END}
Duration:           $(($(date +%s) - $(date -d "${DESTROY_START}" +%s))) seconds

ARTIFACTS
---------
Log File:           ${LOG_FILE}
Evidence File:      ${EVIDENCE_DIR}/decommission_${TIMESTAMP}.json
$(if [[ "${KEEP_EVIDENCE}" == "true" ]]; then
    echo "Evidence Bucket:    gs://${EVIDENCE_BUCKET} (PRESERVED)"
fi)

OPERATOR
--------
User:               $(whoami)
Host:               $(hostname)
GCP Account:        $(gcloud auth list --filter=status:ACTIVE --format='value(account)')

COMPLIANCE
----------
Framework:          CMMC Level 2
Controls:           AU.L2-3.3.8, CM.L2-3.4.9, MA.L2-3.7.5

$(if [[ "${DESTROY_STATUS}" == "SUCCESS" ]]; then
    echo "
✓ DECOMMISSIONING COMPLETED SUCCESSFULLY

All infrastructure has been destroyed. Evidence and audit trails have been
preserved according to compliance requirements."
else
    echo "
⚠ DECOMMISSIONING COMPLETED WITH WARNINGS

Some resources may not have been fully destroyed. Please review the logs
and manually verify resource cleanup in the GCP Console."
fi)

================================================================================
EOF

    log SUCCESS "Decommissioning report generated: ${report_file}"

    if [[ "${VERBOSE}" == "true" ]]; then
        cat "${report_file}"
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    # Parse arguments
    parse_args "$@"

    # Initialize
    init_directories

    print_color "${RED}" "
╔══════════════════════════════════════════════════════════════════╗
║               GCP GITEA INFRASTRUCTURE TEARDOWN                  ║
║                    CMMC Level 2 Compliant                        ║
╚══════════════════════════════════════════════════════════════════╝
"

    DESTROY_START=$(date -Iseconds)

    # Validate
    validate_params

    # Set project
    gcloud config set project "${PROJECT_ID}" 2>&1 | tee -a "${LOG_FILE}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log WARNING "DRY RUN MODE - No actual destruction will occur"
    fi

    local expected_count_field="expected_count=unset"
    if [[ "${EXPECTED_COUNT_SET}" == "true" ]]; then
        if [[ "${EXPECTED_COUNT_MIN}" == "${EXPECTED_COUNT_MAX}" ]]; then
            expected_count_field="expected_count=${EXPECTED_COUNT_MIN}"
        else
            expected_count_field="expected_count=${EXPECTED_COUNT_MIN}-${EXPECTED_COUNT_MAX}"
        fi
    fi

    # Audit log entry
    audit_log "DESTROY" "status=START project=${PROJECT_ID} environment=${ENVIRONMENT} var_file=${VAR_FILE:-auto-loaded} dry_run=${DRY_RUN} ${expected_count_field}"

    # Check infrastructure
    check_infrastructure

    # Run safety validation (integrated project and destroy plan validation)
    run_safety_validation

    # Create final backup
    create_final_backup

    # Export evidence
    export_evidence

    # Confirm destruction (this is now a second layer of confirmation after validation)
    confirm_destruction

    # Destroy infrastructure
    if terraform_destroy; then
        # Clean up local files
        cleanup_local
    else
        log ERROR "Infrastructure destruction failed"
        DESTROY_STATUS="FAILED"
    fi

    DESTROY_END=$(date -Iseconds)

    # Generate evidence
    generate_evidence

    # Generate report
    generate_report

    # Audit log final status
    audit_log "DESTROY" "status=${DESTROY_STATUS} project=${PROJECT_ID} environment=${ENVIRONMENT} resources=${RESOURCES_DESTROYED} var_file=${VAR_FILE:-auto-loaded} ${expected_count_field}"

    if [[ "${DESTROY_STATUS}" == "SUCCESS" ]]; then
        print_color "${GREEN}" "
╔══════════════════════════════════════════════════════════════════╗
║            INFRASTRUCTURE SUCCESSFULLY DESTROYED                 ║
╚══════════════════════════════════════════════════════════════════╝

Environment:        ${ENVIRONMENT}
Resources:          ${RESOURCES_DESTROYED} destroyed
Evidence:           $(if [[ "${KEEP_EVIDENCE}" == "true" ]]; then echo "PRESERVED in gs://${EVIDENCE_BUCKET}"; else echo "DESTROYED"; fi)

All infrastructure has been successfully decommissioned.
Compliance evidence has been generated and stored.
"
    else
        print_color "${YELLOW}" "
╔══════════════════════════════════════════════════════════════════╗
║              INFRASTRUCTURE DESTRUCTION INCOMPLETE               ║
╚══════════════════════════════════════════════════════════════════╝

Some resources may still exist. Please check:
- GCP Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}
- Review logs: ${LOG_FILE}

Manual cleanup may be required.
"
    fi

    log INFO "Teardown script completed"

    return 0
}

# Run main function
main "$@"
