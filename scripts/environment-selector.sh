#!/bin/bash
# ==============================================================================
# Interactive Environment Selector Script
# CMMC Level 2 / NIST SP 800-171 Compliant
# ==============================================================================
#
# Purpose: Safely switch between dev/staging/prod environments with validation
#
# Usage: ./environment-selector.sh [options]
#   -e ENVIRONMENT   Direct environment selection: dev|staging|prod (skip menu)
#   -h               Show this help message
#   -v               Verbose output
#
# Examples:
#   ./environment-selector.sh           # Interactive menu
#   ./environment-selector.sh -e dev    # Direct selection
#
# Features:
#   - Interactive menu with validation
#   - Sources environment-specific .env files
#   - Sets gcloud active project
#   - Exports required environment variables
#   - Color-coded confirmations
#   - Audit logging
#   - Safety checks and warnings
#
# Related Documentation:
#   - See docs/SAFE_OPERATIONS_GUIDE.md for operational procedures
#
# CMMC Controls Addressed:
#   - AU.L2-3.3.1: Audit Record Creation
#   - AU.L2-3.3.8: Protection of Audit Information
#   - IA.L2-3.5.1: Identification and Authentication
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TERRAFORM_DIR="${PROJECT_ROOT}/terraform/gcp-gitea"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly AUDIT_LOG="${LOG_DIR}/environment-audit.log"
readonly TIMESTAMP="$(date +%Y-%m-%d_%H:%M:%S)"

# Environment configuration files
readonly ENV_DIR="${TERRAFORM_DIR}"
readonly ENV_DEV="${ENV_DIR}/.env.dev"
readonly ENV_STAGING="${ENV_DIR}/.env.staging"
readonly ENV_PROD="${ENV_DIR}/.env.prod"
readonly ENV_EXAMPLE="${ENV_DIR}/.env.example"

readonly LEGACY_ENV_DEV="${PROJECT_ROOT}/.env.dev"
readonly LEGACY_ENV_STAGING="${PROJECT_ROOT}/.env.staging"
readonly LEGACY_ENV_PROD="${PROJECT_ROOT}/.env.prod"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Flags
VERBOSE=false
DIRECT_ENV=""
PREVIOUS_PROJECT=""
PREVIOUS_ENVIRONMENT="unknown"
PROD_CONFIRMATION="no"

# ==============================================================================
# FUNCTIONS
# ==============================================================================

# Print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Print error message and exit
error_exit() {
    local message="$*"
    print_color "${RED}" "ERROR: ${message}" >&2
    log_audit "environment-selector" "status=FAILED message=\"${message}\""
    exit 1
}

# Print warning message
warn() {
    print_color "${YELLOW}" "WARNING: $*" >&2
}

# Print info message
info() {
    print_color "${CYAN}" "INFO: $*"
}

# Print success message
success() {
    print_color "${GREEN}" "SUCCESS: $*"
}

# Verbose logging
verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        print_color "${BLUE}" "VERBOSE: $*"
    fi
}

# Log to audit file
log_audit() {
    local action="$1"
    shift
    local details="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')

    mkdir -p "${LOG_DIR}"

    printf '[%s] ACTION=%s USER=%s HOST=%s %s\n' \
        "${timestamp}" \
        "${action}" \
        "${USER:-unknown}" \
        "${HOSTNAME:-unknown}" \
        "${details}" >> "${AUDIT_LOG}"

    verbose "Audit log entry created: ${action} - ${details}"
}

# Display help
show_help() {
    cat << EOF
Environment Selector Script

Usage: ${0##*/} [options]

Options:
    -e ENVIRONMENT   Direct environment selection: dev|staging|prod (skip menu)
    -h               Show this help message
    -v               Verbose output

Interactive Mode:
    Run without options to get an interactive menu for environment selection.

Environment Files Expected:
    dev:     ${ENV_DEV}
    staging: ${ENV_STAGING}
    prod:    ${ENV_PROD}

What This Script Does:
    1. Sources environment-specific .env file
    2. Sets gcloud active project (gcloud config set project)
    3. Exports environment variables: ENVIRONMENT, PROJECT_ID, VAR_FILE, TF_VAR_project_id
    4. Validates the configuration
    5. Checks terraform.tfvars status
    6. Creates audit log entry

Examples:
    ${0##*/}              # Interactive menu
    ${0##*/} -e dev       # Direct dev selection
    ${0##*/} -e prod -v   # Verbose prod selection

Related Documentation:
    - docs/SAFE_OPERATIONS_GUIDE.md
    - terraform/gcp-gitea/terraform.tfvars.example

EOF
}

# Display banner
show_banner() {
    print_color "${CYAN}" "╔════════════════════════════════════════════════════════════╗"
    print_color "${CYAN}" "║    Environment Selector - DCG Gitea Platform              ║"
    print_color "${CYAN}" "║    CMMC Level 2 Compliant Configuration                   ║"
    print_color "${CYAN}" "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    verbose "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI not found. Please install Google Cloud SDK."
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        warn "gcloud not authenticated. You may need to run: gcloud auth login"
    fi

    # Check if log directory exists
    if [[ ! -d "${LOG_DIR}" ]]; then
        verbose "Creating log directory: ${LOG_DIR}"
        mkdir -p "${LOG_DIR}"
    fi

    verbose "Prerequisites check complete"
}

# Resolve environment file path, falling back to legacy locations if needed
get_env_file_path() {
    local env_name="$1"
    local primary=""
    local legacy=""

    case "${env_name}" in
        dev)
            primary="${ENV_DEV}"
            legacy="${LEGACY_ENV_DEV}"
            ;;
        staging)
            primary="${ENV_STAGING}"
            legacy="${LEGACY_ENV_STAGING}"
            ;;
        prod)
            primary="${ENV_PROD}"
            legacy="${LEGACY_ENV_PROD}"
            ;;
        *)
            error_exit "Unknown environment: ${env_name}"
            ;;
    esac

    if [[ -f "${primary}" ]]; then
        verbose "Using environment file: ${primary}"
        echo "${primary}"
        return 0
    fi

    if [[ -f "${legacy}" ]]; then
        warn "Environment file missing at ${primary}; falling back to legacy location ${legacy}"
        echo "${legacy}"
        return 0
    fi

    error_exit "Environment file not found for ${env_name}. Expected ${primary}."
}

map_project_to_env() {
    local project="$1"
    case "${project}" in
        "dcg-gitea-dev")
            echo "dev"
            ;;
        "dcg-gitea-stage")
            echo "staging"
            ;;
        "cui-gitea-prod")
            echo "prod"
            ;;
        "unset"|"")
            echo "none"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Source environment file and extract variables
source_environment() {
    local env_name="$1"
    local env_file
    env_file=$(get_env_file_path "${env_name}") || exit 1

    info "Loading ${env_name} environment configuration..."

    # shellcheck disable=SC1090
    set -a
    source "${env_file}"
    set +a

    if [[ -z "${PROJECT_ID:-}" ]]; then
        error_exit "PROJECT_ID not set in ${env_file}"
    fi

    if [[ -z "${ENVIRONMENT:-}" ]]; then
        export ENVIRONMENT="${env_name}"
    fi

    if [[ -z "${VAR_FILE:-}" ]]; then
        export VAR_FILE="terraform.tfvars.${env_name}"
    fi

    export TF_VAR_project_id="${PROJECT_ID}"

    verbose "Environment variables loaded from ${env_file}"
    verbose "PROJECT_ID=${PROJECT_ID}"
    verbose "ENVIRONMENT=${ENVIRONMENT}"
    verbose "VAR_FILE=${VAR_FILE}"
}

# Set gcloud project
set_gcloud_project() {
    local project_id="$1"

    info "Setting gcloud active project to: ${project_id}"

    PREVIOUS_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "unset")
    PREVIOUS_ENVIRONMENT=$(map_project_to_env "${PREVIOUS_PROJECT}")

    if ! gcloud config set project "${project_id}" &> /dev/null; then
        error_exit "Failed to set gcloud project to ${project_id}. Verify project exists and you have access."
    fi

    # Verify it was set correctly
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")

    if [[ "${current_project}" != "${project_id}" ]]; then
        error_exit "Project verification failed. Expected: ${project_id}, Got: ${current_project}"
    fi

    verbose "gcloud project set and verified: ${project_id}"
}

# Check terraform.tfvars status
check_tfvars_status() {
    local var_file="${VAR_FILE:-}"

    echo ""
    print_color "${MAGENTA}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "${MAGENTA}" "Terraform Variable File Status"
    print_color "${MAGENTA}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ -z "${var_file}" ]]; then
        error_exit "VAR_FILE not set for environment ${ENVIRONMENT}"
    fi

    local target_file="${TERRAFORM_DIR}/${var_file}"

    if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        warn "Auto-loaded file exists: terraform.tfvars"
        if grep -q "${PROJECT_ID}" "${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null; then
            warn "terraform.tfvars auto-loads project ${PROJECT_ID}; rename immediately."
        else
            warn "terraform.tfvars does not match ${PROJECT_ID}; remove or rename it."
        fi
    else
        info "No auto-loaded terraform.tfvars file found (SAFE)"
    fi

    if [[ -f "${target_file}" ]]; then
        success "Environment-specific file exists: ${var_file}"
        info "Use: terraform plan -var-file=${var_file}"
    else
        warn "Environment-specific file NOT found: ${var_file}"
        info "Generating skeleton variable file at ${target_file}"

        local bucket_value="${TERRAFORM_STATE_BUCKET:-}"
        local prefix_value="${TERRAFORM_STATE_PREFIX:-envs/${ENVIRONMENT}}"

        cat > "${target_file}" <<EOF
# Auto-generated skeleton for ${ENVIRONMENT}
# Populate remaining values per docs/ENVIRONMENT_MANAGEMENT.md

project_id = "${PROJECT_ID}"
region     = "${REGION:-us-central1}"
zone       = "${ZONE:-us-central1-a}"
environment = "${ENVIRONMENT}"

terraform_state_bucket = "${bucket_value}"
terraform_state_prefix = "${prefix_value}"

# TODO: copy remaining values from terraform.tfvars.example as needed
EOF

        success "Skeleton ${var_file} created. Review before running Terraform."
    fi

    print_color "${MAGENTA}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

reinitialize_backend() {
    if ! command -v terraform &> /dev/null; then
        warn "terraform CLI not found in PATH. Skipping backend reconfiguration."
        return 0
    fi

    local bucket="${TERRAFORM_STATE_BUCKET:-}"
    local prefix="${TERRAFORM_STATE_PREFIX:-envs/${ENVIRONMENT}}"
    local var_file_path="${TERRAFORM_DIR}/${VAR_FILE}"

    if [[ -z "${bucket}" ]] && [[ -f "${var_file_path}" ]]; then
        bucket=$(grep -oP 'terraform_state_bucket\s*=\s*"\K[^"]+' "${var_file_path}" 2>/dev/null || echo "")
    fi

    if [[ -z "${bucket}" ]]; then
        warn "terraform_state_bucket not set in environment or ${VAR_FILE}; skipping terraform init."
        return 0
    fi

    info "Reinitializing Terraform backend (bucket: ${bucket}, prefix: ${prefix})..."

    if (cd "${TERRAFORM_DIR}" && terraform init -reconfigure \
        -backend-config="bucket=${bucket}" \
        -backend-config="prefix=${prefix}"); then
        success "Terraform backend reinitialized for ${ENVIRONMENT}"
    else
        warn "terraform init failed. Review the output above."
    fi
}

# Display environment summary
show_environment_summary() {
    echo ""
    print_color "${GREEN}" "╔════════════════════════════════════════════════════════════╗"
    print_color "${GREEN}" "║           Environment Configuration Active                ║"
    print_color "${GREEN}" "╚════════════════════════════════════════════════════════════╝"
    echo ""
    success "Environment:        ${ENVIRONMENT}"
    success "GCP Project ID:     ${PROJECT_ID}"
    success "Terraform Var File: ${VAR_FILE}"
    success "TF_VAR_project_id:  ${TF_VAR_project_id}"
    echo ""

    # Verify gcloud project
    local current_gcloud_project
    current_gcloud_project=$(gcloud config get-value project 2>/dev/null || echo "NOT SET")
    success "gcloud Project:     ${current_gcloud_project}"

    if [[ "${current_gcloud_project}" != "${PROJECT_ID}" ]]; then
        error_exit "VALIDATION FAILED: gcloud project mismatch!"
    fi

    echo ""
    info "Audit log: ${AUDIT_LOG}"
    echo ""

    local bucket_value="${TERRAFORM_STATE_BUCKET:-}"
    if [[ -z "${bucket_value}" ]] && [[ -f "${TERRAFORM_DIR}/${VAR_FILE}" ]]; then
        bucket_value=$(grep -oP 'terraform_state_bucket\s*=\s*"\K[^"]+' "${TERRAFORM_DIR}/${VAR_FILE}" 2>/dev/null || echo "")
    fi
    if [[ -n "${bucket_value}" ]]; then
        info "Terraform state bucket: ${bucket_value}"
    else
        warn "Terraform state bucket not defined; terraform init may fail."
    fi

    local prefix_value="${TERRAFORM_STATE_PREFIX:-envs/${ENVIRONMENT}}"
    info "Terraform state prefix: ${prefix_value}"

    echo ""
    print_color "${GREEN}" "════════════════════════════════════════════════════════════"
    success "Environment configuration validated and active!"
    print_color "${GREEN}" "════════════════════════════════════════════════════════════"
    echo ""

    # Display next steps
    print_color "${CYAN}" "Next Steps:"
    echo "  • Change to terraform directory: cd ${TERRAFORM_DIR}"
    echo "  • Run terraform commands with:   terraform plan -var-file=${VAR_FILE}"
    echo "  • Or use Makefile targets:       make plan ENVIRONMENT=${ENVIRONMENT}"
    echo ""
}

# Interactive menu
show_menu() {
    echo ""
    print_color "${CYAN}" "Select Target Environment:"
    echo ""
    print_color "${GREEN}" "  1) Development (dev)"
    print_color "${YELLOW}" "  2) Staging"
    print_color "${RED}" "  3) Production (PROCEED WITH CAUTION)"
    echo ""
    print_color "${CYAN}" "  0) Cancel/Exit"
    echo ""
}

# Get user selection
get_user_selection() {
    local selection

    while true; do
        show_menu
        read -r -p "Enter your choice [0-3]: " selection

        case "${selection}" in
            1)
                echo "dev"
                return 0
                ;;
            2)
                echo "staging"
                return 0
                ;;
            3)
                # Extra confirmation for production
                echo ""
                warn "You selected PRODUCTION environment!"
                read -r -p "Are you ABSOLUTELY sure? Type 'yes' to confirm: " confirm
                if [[ "${confirm}" == "yes" ]]; then
                    PROD_CONFIRMATION="yes"
                    echo "prod"
                    return 0
                else
                    info "Production selection cancelled."
                    PROD_CONFIRMATION="no"
                    continue
                fi
                ;;
            0)
                info "Environment selection cancelled."
                log_audit "switch-environment" "status=CANCELLED reason=user-cancelled"
                exit 0
                ;;
            *)
                warn "Invalid selection. Please choose 0-3."
                ;;
        esac
    done
}

# Main function
main() {
    show_banner
    check_prerequisites

    local environment=""
    PROD_CONFIRMATION="na"

    # Use direct environment if provided, otherwise show menu
    if [[ -n "${DIRECT_ENV}" ]]; then
        environment="${DIRECT_ENV}"
        info "Direct environment selection: ${environment}"

        # Validate environment value
        case "${environment}" in
            dev|staging|prod)
                # Valid environment
                if [[ "${environment}" == "prod" ]]; then
                    PROD_CONFIRMATION="direct"
                fi
                ;;
            *)
                error_exit "Invalid environment: ${environment}. Must be dev, staging, or prod."
                ;;
        esac
    else
        environment=$(get_user_selection)
        # get_user_selection handles exit on cancel, so we don't need validation here
    fi

    if [[ "${environment}" != "prod" ]]; then
        PROD_CONFIRMATION="na"
    fi

    local current_project_before
    current_project_before=$(gcloud config get-value project 2>/dev/null || echo "unset")
    local current_env_before
    current_env_before=$(map_project_to_env "${current_project_before}")

    # Log the attempt
    log_audit "switch-environment" "status=ATTEMPT from_project=${current_project_before} from_env=${current_env_before} target_env=${environment}"

    # Source environment configuration
    source_environment "${environment}"

    # Set gcloud project
    set_gcloud_project "${PROJECT_ID}"

    # Ensure tfvars file exists and safe
    check_tfvars_status

    # Reinitialize terraform backend for this environment
    reinitialize_backend

    # Display summary
    show_environment_summary

    # Log success
    log_audit "switch-environment" "status=SUCCESS from_project=${PREVIOUS_PROJECT} from_env=${PREVIOUS_ENVIRONMENT} to_env=${ENVIRONMENT} to_project=${PROJECT_ID} prod_confirmation=${PROD_CONFIRMATION} var_file=${VAR_FILE}"

    # Final instructions
    print_color "${YELLOW}" "NOTE: These environment variables are set in the CURRENT shell session."
    print_color "${YELLOW}" "      To use them, either:"
    echo "      1. Source this script:  source ${0}"
    echo "      2. Export variables manually after running this script"
    echo ""
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

while getopts "e:hvV" opt; do
    case "${opt}" in
        e)
            DIRECT_ENV="${OPTARG}"
            ;;
        h)
            show_help
            exit 0
            ;;
        v|V)
            VERBOSE=true
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

shift $((OPTIND-1))

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

main "$@"
