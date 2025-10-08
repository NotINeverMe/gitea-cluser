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
#   -k               Keep evidence bucket after destruction
#   -b               Create final backup before destruction
#   -f               Force destroy without confirmation
#   -n               Dry run - show what would be destroyed
#   -v               Verbose output
#   -h               Show this help message
#
# Examples:
#   ./gcp-destroy.sh -p my-project -e dev                # Standard teardown
#   ./gcp-destroy.sh -p my-project -e prod -k -b        # Keep evidence, backup first
#   ./gcp-destroy.sh -p my-project -e staging -n        # Dry run
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
KEEP_EVIDENCE=false
CREATE_BACKUP=false
FORCE_DESTROY=false
DRY_RUN=false
VERBOSE=false

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

# Show usage
show_help() {
    grep "^#" "$0" | head -29 | tail -27 | sed 's/^# //' | sed 's/^#//'
}

# Parse arguments
parse_args() {
    while getopts "p:e:r:kbfnvh" opt; do
        case ${opt} in
            p)
                PROJECT_ID="${OPTARG}"
                ;;
            e)
                ENVIRONMENT="${OPTARG}"
                ;;
            r)
                REGION="${OPTARG}"
                ;;
            k)
                KEEP_EVIDENCE=true
                ;;
            b)
                CREATE_BACKUP=true
                ;;
            f)
                FORCE_DESTROY=true
                ;;
            n)
                DRY_RUN=true
                ;;
            v)
                VERBOSE=true
                ;;
            h)
                show_help
                exit 0
                ;;
            \?)
                log ERROR "Invalid option: -${OPTARG}"
                show_help
                exit 1
                ;;
        esac
    done
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

    print_color "${RED}" "
╔══════════════════════════════════════════════════════════════════╗
║                      ⚠⚠⚠ DANGER ZONE ⚠⚠⚠                        ║
╠══════════════════════════════════════════════════════════════════╣
║ This will PERMANENTLY DESTROY all infrastructure!                ║
║                                                                   ║
║ Environment:      ${ENVIRONMENT}
║ Project:          ${PROJECT_ID}
║ Resources:        ${RESOURCES_DESTROYED} resources will be destroyed
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

    read -p "Are you absolutely sure? Type 'destroy' to confirm: " -r

    if [[ "${REPLY}" != "destroy" ]]; then
        log WARNING "Destruction cancelled by user"
        exit 0
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

    # Run destroy
    if terraform destroy -auto-approve ${extra_args} 2>&1 | tee -a "${LOG_FILE}"; then
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

    # Check infrastructure
    check_infrastructure

    # Create final backup
    create_final_backup

    # Export evidence
    export_evidence

    # Confirm destruction
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