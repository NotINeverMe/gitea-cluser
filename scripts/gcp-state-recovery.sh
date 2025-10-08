#!/bin/bash
# ==============================================================================
# Terraform State Recovery Script
# Recovers Terraform state from GCS versioned backups
# ==============================================================================
#
# Usage: ./gcp-state-recovery.sh [options]
#   -p PROJECT_ID      GCP Project ID (required)
#   -b BUCKET_NAME     State bucket name (required)
#   -v VERSION         Version number to restore (latest if not specified)
#   -l                 List available state versions
#   -f                 Force recovery without confirmation
#   -d                 Dry-run mode (show what would be restored)
#   -h                 Show this help
#
# This script:
#   1. Lists available state versions from GCS
#   2. Downloads specified version or latest
#   3. Creates backup of current state
#   4. Restores selected state version
#   5. Generates recovery evidence
#
# CMMC Controls: CM.L2-3.4.2, CP.L2-3.11.1
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

# List available state versions
list_versions() {
    log INFO "Fetching state versions from gs://${BUCKET_NAME}/terraform/state/"

    local versions
    versions=$(gcloud storage ls --all-versions \
        "gs://${BUCKET_NAME}/terraform/state/default.tfstate" \
        --project="${PROJECT_ID}" \
        --format="table(name,generation,timeCreated,size)" 2>/dev/null || echo "")

    if [[ -z "${versions}" ]]; then
        log ERROR "No state versions found in bucket ${BUCKET_NAME}"
        exit 1
    fi

    echo ""
    log INFO "Available Terraform State Versions:"
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
        "gs://${BUCKET_NAME}/terraform/state/default.tfstate" \
        --project="${PROJECT_ID}" \
        --format="value(generation)" \
        2>/dev/null | head -1
}

# Download specific state version
download_state_version() {
    local version=$1
    local output_file=$2

    log INFO "Downloading state version ${version}..."

    gcloud storage cp \
        "gs://${BUCKET_NAME}/terraform/state/default.tfstate#${version}" \
        "${output_file}" \
        --project="${PROJECT_ID}"

    log SUCCESS "Downloaded state to ${output_file}"
}

# Backup current state
backup_current_state() {
    local backup_dir="${PROJECT_ROOT}/terraform/gcp-gitea/.state-backups"
    mkdir -p "${backup_dir}"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/terraform.tfstate.backup.${timestamp}"

    if [[ -f "${TERRAFORM_DIR}/terraform.tfstate" ]]; then
        log INFO "Backing up current state..."
        cp "${TERRAFORM_DIR}/terraform.tfstate" "${backup_file}"

        # Calculate SHA256 for integrity
        local checksum
        checksum=$(sha256sum "${backup_file}" | awk '{print $1}')
        log SUCCESS "Current state backed up: ${backup_file}"
        log INFO "Checksum: ${checksum}"

        echo "${backup_file}"
    else
        log WARNING "No current state file found - skipping backup"
        echo ""
    fi
}

# Restore state version
restore_state() {
    local source_file=$1
    local target_file="${TERRAFORM_DIR}/terraform.tfstate"

    log INFO "Restoring state from ${source_file}..."

    # Validate JSON
    if ! jq empty "${source_file}" 2>/dev/null; then
        log ERROR "Invalid JSON in state file - aborting restore"
        exit 1
    fi

    # Copy to target
    cp "${source_file}" "${target_file}"

    # Verify
    local checksum
    checksum=$(sha256sum "${target_file}" | awk '{print $1}')
    log SUCCESS "State restored successfully"
    log INFO "New state checksum: ${checksum}"
}

# Generate recovery evidence
generate_evidence() {
    local version=$1
    local backup_file=$2
    local restored_checksum=$3

    local evidence_dir="${TERRAFORM_DIR}/evidence"
    mkdir -p "${evidence_dir}"

    local evidence_file="${evidence_dir}/state_recovery_$(date +%Y%m%d_%H%M%S).json"

    cat > "${evidence_file}" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "${PROJECT_ID}",
  "bucket": "${BUCKET_NAME}",
  "recovery_details": {
    "state_version_restored": "${version}",
    "previous_state_backup": "${backup_file}",
    "restored_state_checksum": "${restored_checksum}",
    "operator": "$(whoami)",
    "hostname": "$(hostname)"
  },
  "validation": {
    "json_valid": true,
    "terraform_version": "$(terraform version -json | jq -r .terraform_version)"
  },
  "cmmc_controls": [
    "CM.L2-3.4.2 - Baseline Configuration",
    "CP.L2-3.11.1 - Information Backup"
  ],
  "next_steps": [
    "Run 'terraform plan' to verify state",
    "Run 'terraform refresh' to sync with infrastructure",
    "Document reason for recovery in change log"
  ]
}
EOF

    log SUCCESS "Recovery evidence generated: ${evidence_file}"
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

    # Confirm recovery
    if [[ "${FORCE}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        echo ""
        log WARNING "You are about to restore Terraform state to version ${VERSION}"
        log WARNING "This will REPLACE your current state file"
        echo ""
        read -p "Continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log INFO "Recovery cancelled"
            exit 0
        fi
    fi

    # Create temp directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf ${temp_dir}" EXIT

    local downloaded_state="${temp_dir}/terraform.tfstate"

    # Download state version
    download_state_version "${VERSION}" "${downloaded_state}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log INFO "DRY-RUN: Would restore state version ${VERSION}"
        log INFO "DRY-RUN: State file preview:"
        jq '.version, .terraform_version, .serial, .lineage' "${downloaded_state}"
        exit 0
    fi

    # Backup current state
    local backup_file
    backup_file=$(backup_current_state)

    # Restore state
    restore_state "${downloaded_state}"

    # Calculate checksum
    local restored_checksum
    restored_checksum=$(sha256sum "${TERRAFORM_DIR}/terraform.tfstate" | awk '{print $1}')

    # Generate evidence
    generate_evidence "${VERSION}" "${backup_file}" "${restored_checksum}"

    # Success summary
    echo ""
    log SUCCESS "===== State Recovery Complete ====="
    echo ""
    log INFO "Restored version: ${VERSION}"
    log INFO "Previous state backed up: ${backup_file}"
    log INFO "Checksum: ${restored_checksum}"
    echo ""
    log INFO "Next steps:"
    echo "  1. Verify state: cd ${TERRAFORM_DIR} && terraform plan"
    echo "  2. Refresh state: terraform refresh"
    echo "  3. Document recovery in change log"
    echo ""
}

main "$@"
