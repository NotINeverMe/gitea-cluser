#!/bin/bash
# ==============================================================================
# GCP Gitea Admin Password Reset Script
# CMMC Level 2 / NIST SP 800-171 Compliant
# ==============================================================================
#
# Description:
#   Resets Gitea admin password using Secret Manager and OS Login authentication.
#   Works with Identity-Aware Proxy and properly handles CMMC compliance requirements.
#
# Usage: ./gcp-admin-password-reset.sh [options]
#   -p PROJECT_ID     GCP Project ID (required)
#   -z ZONE           GCP Zone (default: us-central1-a)
#   -i INSTANCE       Instance name (default: auto-detect from project)
#   -u USERNAME       Gitea username to reset (default: admin)
#   -s SECRET         Secret Manager secret name (default: gitea-admin-password)
#   -v                Verbose output
#   -h                Show this help message
#
# Examples:
#   # Reset admin password (auto-detect instance)
#   ./gcp-admin-password-reset.sh -p cui-gitea-prod
#
#   # Reset specific user on specific instance
#   ./gcp-admin-password-reset.sh -p cui-gitea-prod -i my-instance -u developer
#
# Requirements:
#   - gcloud CLI authenticated (gcloud auth login)
#   - IAM permissions: compute.instances.list, compute.instances.get,
#     compute.instances.setMetadata, secretmanager.versions.access
#   - OS Login enabled on target instance
#
# Exit Codes:
#   0 - Success
#   1 - Error
#
# CMMC Controls Addressed:
#   - IA.L2-3.5.1: Multi-factor Authentication (via OS Login)
#   - IA.L2-3.5.7: Credential Management
#   - AU.L2-3.3.1: Event Logging
#   - AC.L2-3.1.1: Authorized Access Control
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default values
PROJECT_ID=""
ZONE="us-central1-a"
INSTANCE=""
USERNAME="admin"
SECRET_NAME="gitea-admin-password"
VERBOSE=false

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Required:
  -p PROJECT_ID     GCP Project ID

Optional:
  -z ZONE           GCP Zone (default: us-central1-a)
  -i INSTANCE       Instance name (default: auto-detect)
  -u USERNAME       Gitea username (default: admin)
  -s SECRET         Secret Manager secret name (default: gitea-admin-password)
  -v                Verbose output
  -h                Show this help message

Examples:
  # Reset admin password (auto-detect instance)
  $(basename "$0") -p cui-gitea-prod

  # Reset specific user
  $(basename "$0") -p cui-gitea-prod -u developer

Exit Codes:
  0 - Success
  1 - Error
EOF
}

# ==============================================================================
# PARAMETER PARSING
# ==============================================================================

parse_arguments() {
    local OPTIND
    while getopts "p:z:i:u:s:vh" opt; do
        case "$opt" in
            p) PROJECT_ID="$OPTARG" ;;
            z) ZONE="$OPTARG" ;;
            i) INSTANCE="$OPTARG" ;;
            u) USERNAME="$OPTARG" ;;
            s) SECRET_NAME="$OPTARG" ;;
            v) VERBOSE=true ;;
            h) usage; exit 0 ;;
            *)
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID (-p) is required"
        usage
        exit 1
    fi
}

# ==============================================================================
# INSTANCE DETECTION
# ==============================================================================

detect_instance() {
    if [[ -n "${INSTANCE}" ]]; then
        log_debug "Using specified instance: ${INSTANCE}"
        return
    fi

    log_info "Auto-detecting Gitea instance in project ${PROJECT_ID}..."

    # Try common naming patterns
    local patterns=(
        "${PROJECT_ID}-*-gitea-vm"
        "${PROJECT_ID}-gitea-*"
        "*-gitea-vm"
        "gitea-*-server"
    )

    for pattern in "${patterns[@]}"; do
        log_debug "Searching for pattern: ${pattern}"
        local instances=$(gcloud compute instances list \
            --project="${PROJECT_ID}" \
            --filter="name~'${pattern}'" \
            --format="value(name)" \
            2>/dev/null || echo "")

        if [[ -n "${instances}" ]]; then
            # Take first match if multiple found
            INSTANCE=$(echo "${instances}" | head -1)
            log_success "Detected instance: ${INSTANCE}"
            return
        fi
    done

    log_error "Could not auto-detect Gitea instance"
    log_info "Available instances in project:"
    gcloud compute instances list --project="${PROJECT_ID}" --format="table(name,zone,status)"
    log_info "Please specify instance name with -i flag"
    exit 1
}

# ==============================================================================
# PREREQUISITE CHECKS
# ==============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi

    # Check project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project ${PROJECT_ID}"
        log_info "Check that the project exists and you have access"
        exit 1
    fi

    # Verify instance exists
    if ! gcloud compute instances describe "${INSTANCE}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" &> /dev/null; then
        log_error "Instance ${INSTANCE} not found in zone ${ZONE}"
        exit 1
    fi

    # Verify instance is running
    local status=$(gcloud compute instances describe "${INSTANCE}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" \
        --format="value(status)")

    if [[ "${status}" != "RUNNING" ]]; then
        log_error "Instance ${INSTANCE} is not running (status: ${status})"
        log_info "Start the instance and try again"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# ==============================================================================
# PASSWORD RETRIEVAL
# ==============================================================================

fetch_password() {
    log_info "Fetching password from Secret Manager..."

    # Check if secret exists
    if ! gcloud secrets describe "${SECRET_NAME}" --project="${PROJECT_ID}" &> /dev/null; then
        log_error "Secret ${SECRET_NAME} not found in project ${PROJECT_ID}"
        log_info "Available secrets:"
        gcloud secrets list --project="${PROJECT_ID}" --format="table(name)"
        exit 1
    fi

    # Fetch latest version
    local password=$(gcloud secrets versions access latest \
        --secret="${SECRET_NAME}" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")

    if [[ -z "${password}" ]]; then
        log_error "Failed to retrieve secret ${SECRET_NAME}"
        exit 1
    fi

    echo "${password}"
}

# ==============================================================================
# PASSWORD RESET
# ==============================================================================

reset_password() {
    local new_password="$1"

    log_info "Resetting Gitea admin password via OS Login..."

    # Build the password reset command
    # Run as root to execute docker commands, then switch to git user inside container
    local reset_cmd="sudo docker exec -u git gitea gitea admin user change-password --username ${USERNAME} --password '${new_password}'"

    log_debug "Executing via gcloud compute ssh with IAP tunnel..."

    # Execute via gcloud compute ssh (uses OS Login + IAP automatically)
    if gcloud compute ssh "${INSTANCE}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" \
        --tunnel-through-iap \
        --command="${reset_cmd}" 2>&1 | tee /tmp/password-reset.log; then

        log_success "Password reset command executed successfully"
        return 0
    else
        log_error "Password reset command failed"
        log_info "Check /tmp/password-reset.log for details"
        return 1
    fi
}

# ==============================================================================
# VERIFICATION
# ==============================================================================

verify_reset() {
    log_info "Verifying password reset..."

    # Check Gitea logs for password change event
    local verify_cmd="sudo docker logs gitea --tail 50 2>&1 | grep -i 'password.*changed\|admin.*user.*change' || echo 'No password change logs found'"

    log_debug "Checking Gitea container logs..."

    gcloud compute ssh "${INSTANCE}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" \
        --tunnel-through-iap \
        --command="${verify_cmd}"

    echo
    log_info "Password reset complete. Please test login:"
    echo
    echo -e "${CYAN}  URL:${NC} https://$(gcloud compute instances describe "${INSTANCE}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" \
        --format="value(metadata.items[key='gitea-domain'].value)" 2>/dev/null || echo "gitea.example.com")"
    echo -e "${CYAN}  Username:${NC} ${USERNAME}"
    echo -e "${CYAN}  Password:${NC} (from Secret Manager: ${SECRET_NAME})"
    echo
}

# ==============================================================================
# EVIDENCE GENERATION
# ==============================================================================

generate_evidence() {
    local evidence_dir="${PROJECT_ROOT}/terraform/gcp-gitea/evidence"
    mkdir -p "${evidence_dir}"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local evidence_file="${evidence_dir}/password-reset-${USERNAME}-$(date +%Y%m%d_%H%M%S).json"

    cat > "${evidence_file}" <<EOF
{
  "timestamp": "${timestamp}",
  "operation": "admin-password-reset",
  "project_id": "${PROJECT_ID}",
  "zone": "${ZONE}",
  "instance": "${INSTANCE}",
  "username": "${USERNAME}",
  "secret_name": "${SECRET_NAME}",
  "compliance": {
    "cmmc_controls": ["IA.L2-3.5.1", "IA.L2-3.5.7", "AU.L2-3.3.1", "AC.L2-3.1.1"],
    "nist_controls": ["IA-5", "IA-2", "AU-3", "AC-2"]
  },
  "method": "gcloud-compute-ssh-os-login",
  "status": "success"
}
EOF

    log_success "Evidence saved to: ${evidence_file}"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    log "Starting Gitea admin password reset..."
    echo

    # Parse arguments
    parse_arguments "$@"

    # Display configuration
    log_info "Configuration:"
    log_info "  Project: ${PROJECT_ID}"
    log_info "  Zone: ${ZONE}"
    log_info "  Instance: ${INSTANCE:-<auto-detect>}"
    log_info "  Username: ${USERNAME}"
    log_info "  Secret: ${SECRET_NAME}"
    echo

    # Auto-detect instance if not specified
    detect_instance

    # Check prerequisites
    check_prerequisites
    echo

    # Fetch new password from Secret Manager
    local new_password=$(fetch_password)
    log_success "Password retrieved from Secret Manager"
    echo

    # Reset password
    if reset_password "${new_password}"; then
        echo
        verify_reset
        echo
        generate_evidence
        echo
        log_success "Admin password reset completed successfully!"
        log_info "You can now log in to Gitea with the new password"
    else
        echo
        log_error "Password reset failed"
        log_info "Common issues:"
        log_info "  1. OS Login not enabled on instance"
        log_info "  2. Gitea container not running"
        log_info "  3. IAM permissions missing"
        log_info "  4. Firewall blocking IAP tunnel"
        exit 1
    fi
}

# Run main function
main "$@"
