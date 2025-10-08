#!/bin/bash
# ==============================================================================
# Configuration Rollback Script
# Rolls back terraform.tfvars to previous versioned configuration from GCS
# ==============================================================================
#
# Usage: ./gcp-config-rollback.sh [options]
#   -p PROJECT_ID      GCP Project ID (required)
#   -b BUCKET_NAME     Config bucket name (required)
#   -v VERSION         Version number to rollback to (latest if not specified)
#   -l                 List available config versions
#   -f                 Force rollback without confirmation
#   -d                 Dry-run mode (show what would be restored)
#   -h                 Show this help
#
# This script:
#   1. Lists available terraform.tfvars versions from GCS
#   2. Downloads specified version
#   3. Creates backup of current config
#   4. Restores selected config version
#   5. Validates configuration
#   6. Generates rollback evidence
#
# CMMC Controls: CM.L2-3.4.2, AU.L2-3.3.1
# ==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TERRAFORM_DIR="${PROJECT_ROOT}/terraform/gcp-gitea"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
PROJECT_ID=""
BUCKET_NAME=""
VERSION=""
LIST_ONLY=false
FORCE=false
DRY_RUN=false

# Print colored output
log() {
    local level=$1
    shift
    case "${level}" in
        ERROR)   echo -e "${RED}✗ $*${NC}" >&2 ;;
        SUCCESS) echo -e "${GREEN}✓ $*${NC}" ;;
        WARNING) echo -e "${YELLOW}⚠ $*${NC}" ;;
        INFO)    echo -e "${BLUE}ℹ $*${NC}" ;;
    esac
}

show_help() {
    head -22 "$0" | tail -20 | sed 's/^# //'
}

# List available config versions
list_versions() {
    log INFO "Fetching config versions from gs://${BUCKET_NAME}/terraform/configs/"

    local versions
    versions=$(gcloud storage ls --all-versions \
        "gs://${BUCKET_NAME}/terraform/configs/terraform.tfvars" \
        --project="${PROJECT_ID}" \
        --format="table(name,generation,timeCreated,size,metadata.config_version)" 2>/dev/null || echo "")

    if [[ -z "${versions}" ]]; then
        log ERROR "No config versions found in bucket ${BUCKET_NAME}"
        exit 1
    fi

    echo ""
    log INFO "Available Configuration Versions:"
    echo ""
    echo "${versions}"
    echo ""

    # Count versions
    local count
    count=$(echo "${versions}" | tail -n +2 | wc -l)
    log INFO "Total versions: ${count}"

    return 0
}

# Get latest version number
get_latest_version() {
    gcloud storage ls --all-versions \
        "gs://${BUCKET_NAME}/terraform/configs/terraform.tfvars" \
        --project="${PROJECT_ID}" \
        --format="value(generation)" \
        2>/dev/null | head -1
}

# Download specific config version
download_config_version() {
    local version=$1
    local output_file=$2

    log INFO "Downloading config version ${version}..."

    gcloud storage cp \
        "gs://${BUCKET_NAME}/terraform/configs/terraform.tfvars#${version}" \
        "${output_file}" \
        --project="${PROJECT_ID}"

    log SUCCESS "Downloaded config to ${output_file}"
}

# Backup current config
backup_current_config() {
    local backup_dir="${TERRAFORM_DIR}/.config-backups"
    mkdir -p "${backup_dir}"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/terraform.tfvars.backup.${timestamp}"

    if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        log INFO "Backing up current config..."
        cp "${TERRAFORM_DIR}/terraform.tfvars" "${backup_file}"

        # Calculate SHA256 for integrity
        local checksum
        checksum=$(sha256sum "${backup_file}" | awk '{print $1}')
        log SUCCESS "Current config backed up: ${backup_file}"
        log INFO "Checksum: ${checksum}"

        echo "${backup_file}"
    else
        log WARNING "No current terraform.tfvars found - skipping backup"
        echo ""
    fi
}

# Validate configuration
validate_config() {
    local config_file=$1

    log INFO "Validating configuration..."

    # Check for secrets in config (should be none)
    if grep -iE "(password|secret|key|token).*=.*['\"].*['\"]" "${config_file}" | grep -v "secret_name\|key_name\|_ref" > /dev/null; then
        log ERROR "Configuration contains hardcoded secrets - validation failed"
        log ERROR "All secrets must reference Secret Manager"
        return 1
    fi

    # Validate Terraform syntax
    cd "${TERRAFORM_DIR}"
    if ! terraform validate -test-directory=. > /dev/null 2>&1; then
        log ERROR "Terraform validation failed - config may be incompatible"
        return 1
    fi

    log SUCCESS "Configuration validation passed"
    return 0
}

# Restore config version
restore_config() {
    local source_file=$1
    local target_file="${TERRAFORM_DIR}/terraform.tfvars"

    log INFO "Restoring config from ${source_file}..."

    # Copy to target
    cp "${source_file}" "${target_file}"

    # Verify
    local checksum
    checksum=$(sha256sum "${target_file}" | awk '{print $1}')
    log SUCCESS "Config restored successfully"
    log INFO "New config checksum: ${checksum}"
}

# Generate rollback evidence
generate_evidence() {
    local version=$1
    local backup_file=$2
    local restored_checksum=$3

    local evidence_dir="${TERRAFORM_DIR}/evidence"
    mkdir -p "${evidence_dir}"

    local evidence_file="${evidence_dir}/config_rollback_$(date +%Y%m%d_%H%M%S).json"

    # Extract config diff
    local config_diff=""
    if [[ -n "${backup_file}" ]] && [[ -f "${backup_file}" ]]; then
        config_diff=$(diff -u "${backup_file}" "${TERRAFORM_DIR}/terraform.tfvars" || true)
    fi

    cat > "${evidence_file}" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "${PROJECT_ID}",
  "bucket": "${BUCKET_NAME}",
  "rollback_details": {
    "config_version_restored": "${version}",
    "previous_config_backup": "${backup_file}",
    "restored_config_checksum": "${restored_checksum}",
    "operator": "$(whoami)",
    "hostname": "$(hostname)"
  },
  "validation": {
    "no_secrets_in_config": true,
    "terraform_validate_passed": true
  },
  "cmmc_controls": [
    "CM.L2-3.4.2 - Baseline Configuration",
    "AU.L2-3.3.1 - Audit and Accountability"
  ],
  "next_steps": [
    "Run 'terraform plan' to see infrastructure changes",
    "Review diff between old and new config",
    "Document rollback reason in change log",
    "Update configuration version in GCS if changes needed"
  ]
}
EOF

    log SUCCESS "Rollback evidence generated: ${evidence_file}"

    # Show diff if available
    if [[ -n "${config_diff}" ]]; then
        echo ""
        log INFO "Configuration changes:"
        echo "${config_diff}" | head -30
        echo ""
    fi
}

# Main function
main() {
    # Parse arguments
    while getopts "p:b:v:lfdhx" opt; do
        case ${opt} in
            p) PROJECT_ID="${OPTARG}" ;;
            b) BUCKET_NAME="${OPTARG}" ;;
            v) VERSION="${OPTARG}" ;;
            l) LIST_ONLY=true ;;
            f) FORCE=true ;;
            d) DRY_RUN=true ;;
            h) show_help; exit 0 ;;
            *) show_help; exit 1 ;;
        esac
    done

    # Validate required arguments
    if [[ -z "${PROJECT_ID}" ]]; then
        log ERROR "Project ID is required (-p)"
        show_help
        exit 1
    fi

    if [[ -z "${BUCKET_NAME}" ]]; then
        log ERROR "Bucket name is required (-b)"
        show_help
        exit 1
    fi

    # List versions if requested
    if [[ "${LIST_ONLY}" == "true" ]]; then
        list_versions
        exit 0
    fi

    # Determine version to restore
    if [[ -z "${VERSION}" ]]; then
        log INFO "No version specified - using latest"
        VERSION=$(get_latest_version)
        if [[ -z "${VERSION}" ]]; then
            log ERROR "Could not determine latest version"
            exit 1
        fi
        log INFO "Latest version: ${VERSION}"
    fi

    # Confirm rollback
    if [[ "${FORCE}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        echo ""
        log WARNING "You are about to rollback configuration to version ${VERSION}"
        log WARNING "This will REPLACE your current terraform.tfvars file"
        echo ""
        read -p "Continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log INFO "Rollback cancelled"
            exit 0
        fi
    fi

    # Create temp directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf ${temp_dir}" EXIT

    local downloaded_config="${temp_dir}/terraform.tfvars"

    # Download config version
    download_config_version "${VERSION}" "${downloaded_config}"

    # Validate config
    if ! validate_config "${downloaded_config}"; then
        log ERROR "Configuration validation failed - rollback aborted"
        exit 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log INFO "DRY-RUN: Would rollback to config version ${VERSION}"
        log INFO "DRY-RUN: Configuration preview:"
        cat "${downloaded_config}"
        exit 0
    fi

    # Backup current config
    local backup_file
    backup_file=$(backup_current_config)

    # Restore config
    restore_config "${downloaded_config}"

    # Calculate checksum
    local restored_checksum
    restored_checksum=$(sha256sum "${TERRAFORM_DIR}/terraform.tfvars" | awk '{print $1}')

    # Generate evidence
    generate_evidence "${VERSION}" "${backup_file}" "${restored_checksum}"

    # Success summary
    echo ""
    log SUCCESS "===== Configuration Rollback Complete ====="
    echo ""
    log INFO "Restored version: ${VERSION}"
    log INFO "Previous config backed up: ${backup_file}"
    log INFO "Checksum: ${restored_checksum}"
    echo ""
    log INFO "Next steps:"
    echo "  1. Review changes: cd ${TERRAFORM_DIR} && terraform plan"
    echo "  2. Apply if needed: terraform apply"
    echo "  3. Document rollback reason"
    echo ""
}

main "$@"
