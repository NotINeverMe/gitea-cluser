#!/bin/bash
# ==============================================================================
# Terraform Project Validator
# Validates GCP project context before Terraform operations
# ==============================================================================
#
# Usage: ./terraform-project-validator.sh [options]
#   --operation=<plan|apply|destroy>  Type of operation (default: plan)
#   --project=<project-id>            Expected project ID (optional)
#   --terraform-dir=<path>            Terraform directory (default: pwd)
#   --test-mode                       Run in test mode (no actual changes)
#   -v, --verbose                     Verbose output
#   -h, --help                        Show this help
#
# Exit Codes:
#   0 - All validations passed
#   1 - Validation failed (mismatch detected)
#   2 - Missing configuration
#   3 - Invalid usage
#
# Example:
#   ./terraform-project-validator.sh --operation=destroy --project=cui-gitea-prod
#
# CMMC Controls: CM.L2-3.4.2 (Configuration Management)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="/tmp/tf-validation_${TIMESTAMP}.log"
readonly AUDIT_LOG="${PROJECT_ROOT}/logs/environment-audit.log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Validation state
VALIDATION_PASSED=true
VALIDATION_WARNINGS=0
VALIDATION_ERRORS=0

# Options
OPERATION="plan"
EXPECTED_PROJECT=""
TERRAFORM_DIR="${PWD}"
TEST_MODE=false
VERBOSE=false
VAR_FILE=""
NON_INTERACTIVE=false
CONFIRM_DESTROY=false

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

    if [[ "${VERBOSE}" == "true" ]]; then
        echo "${message}"
    fi
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

# Print section header
print_section() {
    local title=$1
    echo ""
    print_color "${CYAN}${BOLD}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "${CYAN}${BOLD}" "  $title"
    print_color "${CYAN}${BOLD}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Print check result
print_check() {
    local status=$1
    local message=$2
    local details=${3:-}

    if [[ "${status}" == "PASS" ]]; then
        print_color "${GREEN}" "  ✅ ${message}"
        [[ -n "${details}" ]] && print_color "${GREEN}" "     ${details}"
    elif [[ "${status}" == "WARN" ]]; then
        print_color "${YELLOW}" "  ⚠️  ${message}"
        [[ -n "${details}" ]] && print_color "${YELLOW}" "     ${details}"
        ((VALIDATION_WARNINGS++))
    elif [[ "${status}" == "FAIL" ]]; then
        print_color "${RED}" "  ❌ ${message}"
        [[ -n "${details}" ]] && print_color "${RED}" "     ${details}"
        ((VALIDATION_ERRORS++))
        VALIDATION_PASSED=false
    else
        echo "  ℹ️  ${message}"
        [[ -n "${details}" ]] && echo "     ${details}"
    fi

    log "CHECK" "${status}: ${message} ${details}"
}

# Show usage
show_usage() {
    cat << EOF
Terraform Project Validator

Validates GCP project context before Terraform operations to prevent
accidental operations on the wrong project.

Usage: $(basename "$0") [options]

Options:
  --operation=<type>        Type of operation: plan, apply, destroy (default: plan)
  --project=<project-id>    Expected project ID to validate against
  --terraform-dir=<path>    Path to Terraform directory (default: current directory)
  --test-mode               Run in test mode without actual validation
  -v, --verbose             Enable verbose output
  -h, --help                Show this help message

Examples:
  # Validate before plan
  $(basename "$0") --operation=plan

  # Validate before destroy with expected project
  $(basename "$0") --operation=destroy --project=cui-gitea-prod

  # Validate specific Terraform directory
  $(basename "$0") --terraform-dir=/path/to/terraform

Exit Codes:
  0  All validations passed
  1  Validation failed (project mismatch)
  2  Missing required configuration
  3  Invalid usage

For more information, see docs/SAFE_OPERATIONS_GUIDE.md
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --operation=*)
                OPERATION="${1#*=}"
                ;;
            --project=*)
                EXPECTED_PROJECT="${1#*=}"
                ;;
            --terraform-dir=*)
                TERRAFORM_DIR="${1#*=}"
                ;;
            --var-file=*)
                VAR_FILE="${1#*=}"
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                ;;
            --confirm-destroy)
                CONFIRM_DESTROY=true
                ;;
            --test-mode)
                TEST_MODE=true
                ;;
            -v|--verbose)
                VERBOSE=true
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_color "${RED}" "Unknown option: $1"
                show_usage
                exit 3
                ;;
        esac
        shift
    done
}

# Validate gcloud is installed and authenticated
check_gcloud() {
    print_section "GCloud Configuration"

    if ! command -v gcloud &> /dev/null; then
        print_check "FAIL" "gcloud CLI not found" "Install from https://cloud.google.com/sdk"
        return 1
    fi

    print_check "PASS" "gcloud CLI installed" "$(gcloud version | head -1)"

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_check "FAIL" "No active gcloud authentication" "Run: gcloud auth login"
        return 1
    fi

    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
    print_check "PASS" "Authenticated account" "${active_account}"

    return 0
}

# Validate GCP project context
check_gcp_project() {
    print_section "GCP Project Validation"

    local gcloud_project=$(gcloud config get-value project 2>/dev/null)

    if [[ -z "${gcloud_project}" ]]; then
        print_check "FAIL" "No active GCP project in gcloud config" "Run: gcloud config set project <project-id>"
        return 1
    fi

    print_check "INFO" "Active GCP project" "${gcloud_project}"

    # If expected project is provided, validate match
    if [[ -n "${EXPECTED_PROJECT}" ]]; then
        if [[ "${gcloud_project}" == "${EXPECTED_PROJECT}" ]]; then
            print_check "PASS" "Project matches expected" "${gcloud_project} == ${EXPECTED_PROJECT}"
        else
            print_check "FAIL" "Project mismatch" "Expected: ${EXPECTED_PROJECT}, Got: ${gcloud_project}"
            return 1
        fi
    else
        print_check "WARN" "No expected project specified" "Cannot validate if this is the intended target"
    fi

    # Store for later checks
    GCLOUD_PROJECT="${gcloud_project}"

    return 0
}

# Check Terraform installation
check_terraform() {
    print_section "Terraform Installation"

    if ! command -v terraform &> /dev/null; then
        print_check "FAIL" "Terraform not found" "Install from https://www.terraform.io"
        return 1
    fi

    local tf_version=$(terraform version | head -1)
    print_check "PASS" "Terraform installed" "${tf_version}"

    return 0
}

# Validate Terraform directory
check_terraform_directory() {
    print_section "Terraform Directory"

    if [[ ! -d "${TERRAFORM_DIR}" ]]; then
        print_check "FAIL" "Terraform directory not found" "${TERRAFORM_DIR}"
        return 1
    fi

    print_check "PASS" "Directory exists" "${TERRAFORM_DIR}"

    # Check for Terraform files
    if ! ls "${TERRAFORM_DIR}"/*.tf &> /dev/null; then
        print_check "FAIL" "No .tf files found" "${TERRAFORM_DIR}"
        return 1
    fi

    local tf_file_count=$(ls -1 "${TERRAFORM_DIR}"/*.tf 2>/dev/null | wc -l)
    print_check "PASS" "Terraform files found" "${tf_file_count} .tf files"

    # Change to Terraform directory for subsequent checks
    cd "${TERRAFORM_DIR}" || return 1

    return 0
}

# Check Terraform initialization
check_terraform_init() {
    print_section "Terraform Initialization"

    if [[ ! -d ".terraform" ]]; then
        print_check "FAIL" "Terraform not initialized" "Run: terraform init"
        return 1
    fi

    print_check "PASS" "Terraform initialized" ".terraform directory exists"

    # Check backend configuration
    if [[ -f "backend.tf" ]]; then
        local backend_bucket=$(grep -oP 'bucket\s*=\s*"\K[^"]+' backend.tf 2>/dev/null || echo "")
        if [[ -n "${backend_bucket}" ]]; then
            print_check "PASS" "Backend configured" "Bucket: ${backend_bucket}"

            # Validate backend bucket contains project ID
            if [[ -n "${GCLOUD_PROJECT}" ]] && [[ "${backend_bucket}" == *"${GCLOUD_PROJECT}"* ]]; then
                print_check "PASS" "Backend bucket matches gcloud project" "${backend_bucket} contains ${GCLOUD_PROJECT}"
            else
                print_check "WARN" "Backend bucket may not match project" "Bucket: ${backend_bucket}, Project: ${GCLOUD_PROJECT}"
            fi
        fi
    else
        print_check "WARN" "No backend.tf found" "Using local state"
    fi

    return 0
}

# Check Terraform state
check_terraform_state() {
    print_section "Terraform State Validation"

    # Try to get state
    if ! terraform state list &> /dev/null; then
        print_check "WARN" "Unable to read Terraform state" "State may be empty or inaccessible"
        return 0
    fi

    local resource_count=$(terraform state list 2>/dev/null | wc -l)

    if [[ ${resource_count} -eq 0 ]]; then
        print_check "INFO" "Terraform state is empty" "No resources currently managed"
        return 0
    fi

    print_check "PASS" "Terraform state accessible" "${resource_count} resources in state"

    # Sample resources to check project ID
    local sample_resources=$(terraform show -json 2>/dev/null | grep -oP '"project":\s*"\K[^"]+' | head -5 | sort -u)

    if [[ -n "${sample_resources}" ]]; then
        local unique_projects=$(echo "${sample_resources}" | wc -l)

        if [[ ${unique_projects} -eq 1 ]]; then
            local state_project=$(echo "${sample_resources}" | head -1)
            print_check "INFO" "State project ID" "${state_project}"

            if [[ "${state_project}" == "${GCLOUD_PROJECT}" ]]; then
                print_check "PASS" "State project matches gcloud" "${state_project} == ${GCLOUD_PROJECT}"
            else
                print_check "FAIL" "State project mismatch" "State: ${state_project}, gcloud: ${GCLOUD_PROJECT}"
                return 1
            fi

            if [[ -n "${EXPECTED_PROJECT}" ]] && [[ "${state_project}" != "${EXPECTED_PROJECT}" ]]; then
                print_check "FAIL" "State project does not match expected" "State: ${state_project}, Expected: ${EXPECTED_PROJECT}"
                return 1
            fi
        else
            print_check "WARN" "Multiple projects found in state" "${unique_projects} different project IDs"
            echo "${sample_resources}" | while read -r proj; do
                echo "       - ${proj}"
            done
        fi
    fi

    return 0
}

# Check variable files
check_variable_files() {
    print_section "Variable Files"

    # List all tfvars files
    local tfvars_files=$(ls -1 *.tfvars 2>/dev/null || echo "")

    if [[ -z "${tfvars_files}" ]]; then
        print_check "INFO" "No .tfvars files found" "Using default values or -var flags"
    else
        print_check "INFO" "Variable files found:"
        echo "${tfvars_files}" | while read -r file; do
            echo "       - ${file}"

            # Check for project_id in file
            if grep -q "project_id" "${file}" 2>/dev/null; then
                local proj_id=$(grep -oP 'project_id\s*=\s*"\K[^"]+' "${file}" 2>/dev/null || echo "")
                if [[ -n "${proj_id}" ]]; then
                    echo "         project_id = ${proj_id}"

                    # Validate against gcloud project
                    if [[ "${proj_id}" == "${GCLOUD_PROJECT}" ]]; then
                        print_check "PASS" "${file} matches gcloud project" "${proj_id}"
                    else
                        print_check "WARN" "${file} does not match gcloud" "File: ${proj_id}, gcloud: ${GCLOUD_PROJECT}"
                    fi
                fi
            fi
        done
    fi

    # Explicit var-file requirement
    if [[ -z "${VAR_FILE}" ]]; then
        if [[ "${OPERATION}" == "destroy" ]]; then
            print_check "FAIL" "No --var-file specified for destroy operation" "Destructive operations require explicit variable file"
            return 1
        else
            print_check "WARN" "No --var-file specified" "Provide --var-file to ensure explicit environment selection"
        fi
    else
        local var_file_path="${VAR_FILE}"
        if [[ ! -f "${var_file_path}" ]]; then
            local var_basename
            var_basename=$(basename "${VAR_FILE}")
            if [[ -f "${var_basename}" ]]; then
                var_file_path="${var_basename}"
            fi
        fi

        if [[ ! -f "${var_file_path}" ]]; then
            print_check "FAIL" "Variable file not found" "${var_file_path}"
            return 1
        fi

        local varfile_project
        varfile_project=$(grep -oP 'project_id\s*=\s*"\K[^"]+' "${var_file_path}" 2>/dev/null || echo "")

        print_check "PASS" "Using explicit variable file" "${var_file_path}"

        if [[ -z "${varfile_project}" ]]; then
            print_check "WARN" "project_id not found in ${var_file_path}"
        else
            if [[ -n "${EXPECTED_PROJECT}" ]] && [[ "${varfile_project}" != "${EXPECTED_PROJECT}" ]]; then
                print_check "FAIL" "Variable file project_id mismatch" "Expected: ${EXPECTED_PROJECT}, Got: ${varfile_project}"
                return 1
            fi

            if [[ "${varfile_project}" == "${GCLOUD_PROJECT}" ]]; then
                print_check "PASS" "Variable file project matches gcloud project" "${varfile_project}"
            else
                print_check "FAIL" "Variable file project does not match gcloud" "Var file: ${varfile_project}, gcloud: ${GCLOUD_PROJECT}"
                return 1
            fi
        fi
    fi

    # Check for terraform.tfvars (auto-loaded - dangerous!)
    if [[ -f "terraform.tfvars" ]]; then
        print_check "WARN" "terraform.tfvars exists (auto-loaded)" "⚠️  This file is automatically loaded by Terraform"
        print_color "${YELLOW}" "     Recommendation: Use explicit -var-file parameter instead"

        local auto_proj=$(grep -oP 'project_id\s*=\s*"\K[^"]+' terraform.tfvars 2>/dev/null || echo "")
        if [[ -n "${auto_proj}" ]]; then
            print_color "${YELLOW}" "     Auto-loaded project_id: ${auto_proj}"

            if [[ "${auto_proj}" != "${GCLOUD_PROJECT}" ]]; then
                print_check "FAIL" "Auto-loaded project mismatch" "terraform.tfvars: ${auto_proj}, gcloud: ${GCLOUD_PROJECT}"
                print_color "${RED}" "     ⚠️  DANGER: Terraform will use ${auto_proj}, but gcloud is ${GCLOUD_PROJECT}!"
                return 1
            fi
        fi
    fi

    return 0
}

# Check for destructive operation safeguards
check_destroy_safeguards() {
    if [[ "${OPERATION}" != "destroy" ]]; then
        return 0
    fi

    print_section "Destroy Operation Safeguards"

    # Check if destroy plan exists
    if [[ ! -f "destroy.tfplan" ]]; then
        print_check "WARN" "No destroy plan found" "Generate plan first: terraform plan -destroy -out=destroy.tfplan"
    else
        print_check "PASS" "Destroy plan exists" "destroy.tfplan"

        # Check plan age
        local plan_age=$(($(date +%s) - $(stat -c %Y destroy.tfplan 2>/dev/null || stat -f %m destroy.tfplan 2>/dev/null)))
        if [[ ${plan_age} -gt 3600 ]]; then
            print_check "WARN" "Destroy plan is old" "Age: $((plan_age / 60)) minutes. Consider regenerating."
        fi
    fi

    # Warn about operation type
    print_color "${RED}${BOLD}" "  ⚠️  DESTRUCTIVE OPERATION DETECTED"
    print_color "${RED}" "     This operation will DELETE resources permanently!"
    print_color "${YELLOW}" "     Ensure you have:"
    print_color "${YELLOW}" "     - Generated and reviewed destroy plan"
    print_color "${YELLOW}" "     - Verified correct project: ${GCLOUD_PROJECT}"
    print_color "${YELLOW}" "     - Created backups of critical data"
    print_color "${YELLOW}" "     - Obtained necessary approvals"

    return 0
}

require_confirmation() {
    if [[ "${OPERATION}" != "destroy" ]]; then
        return 0
    fi

    if [[ "${TEST_MODE}" == "true" ]]; then
        return 0
    fi

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        if [[ "${CONFIRM_DESTROY}" == "true" ]]; then
            print_color "${GREEN}" "  Non-interactive confirmation accepted"
            return 0
        fi

        print_check "FAIL" "Non-interactive mode requires --confirm-destroy flag"
        return 1
    fi

    echo ""
    print_color "${RED}${BOLD}" "  ⚠️  FINAL CONFIRMATION REQUIRED ⚠️"
    print_color "${RED}" "     This validation is for a destructive destroy operation."
    print_color "${RED}" "     Double-confirm you intend to target project: ${GCLOUD_PROJECT}"
    echo ""

    read -r -p "  Type the project ID to confirm (${GCLOUD_PROJECT}): " confirm_project
    if [[ "${confirm_project}" != "${GCLOUD_PROJECT}" ]]; then
        print_check "FAIL" "Project confirmation mismatch" "Expected: ${GCLOUD_PROJECT}, Got: ${confirm_project:-<empty>}"
        return 1
    fi
    print_check "PASS" "Project ID confirmed"

    read -r -p "  Type DESTROY (all caps) to proceed: " confirm_word
    if [[ "${confirm_word}" != "DESTROY" ]]; then
        print_check "FAIL" "Destroy confirmation not received"
        return 1
    fi
    print_check "PASS" "Destructive action confirmed"

    return 0
}

# Generate validation summary
generate_summary() {
    print_section "Validation Summary"

    echo ""
    print_color "${CYAN}${BOLD}" "  Context Summary:"
    print_color "${CYAN}" "    GCloud Project:      ${GCLOUD_PROJECT}"
    print_color "${CYAN}" "    Terraform Directory: ${TERRAFORM_DIR}"
    print_color "${CYAN}" "    Operation Type:      ${OPERATION}"
    [[ -n "${EXPECTED_PROJECT}" ]] && print_color "${CYAN}" "    Expected Project:    ${EXPECTED_PROJECT}"
    [[ -n "${VAR_FILE}" ]] && print_color "${CYAN}" "    Variable File:       ${VAR_FILE}"
    echo ""

    print_color "${CYAN}${BOLD}" "  Validation Results:"
    print_color "${CYAN}" "    Errors:   ${VALIDATION_ERRORS}"
    print_color "${CYAN}" "    Warnings: ${VALIDATION_WARNINGS}"
    echo ""

    if [[ "${VALIDATION_PASSED}" == "true" ]]; then
        if [[ ${VALIDATION_WARNINGS} -eq 0 ]]; then
            print_color "${GREEN}${BOLD}" "  ✅ ALL VALIDATIONS PASSED"
            print_color "${GREEN}" "     Safe to proceed with Terraform ${OPERATION}"
        else
            print_color "${YELLOW}${BOLD}" "  ⚠️  VALIDATION PASSED WITH WARNINGS"
            print_color "${YELLOW}" "     Review warnings before proceeding"
        fi

        # Additional guidance for destructive operations
        if [[ "${OPERATION}" == "destroy" ]]; then
            echo ""
            print_color "${YELLOW}${BOLD}" "  ⚠️  DESTRUCTIVE OPERATION CHECKLIST:"
            print_color "${YELLOW}" "     [ ] Destroy plan generated and reviewed"
            print_color "${YELLOW}" "     [ ] Resource count validated"
            print_color "${YELLOW}" "     [ ] Backups verified"
            print_color "${YELLOW}" "     [ ] Approvals obtained"
            print_color "${YELLOW}" "     [ ] Project confirmed: ${GCLOUD_PROJECT}"
        fi
    else
        print_color "${RED}${BOLD}" "  ❌ VALIDATION FAILED"
        print_color "${RED}" "     DO NOT proceed with Terraform ${OPERATION}"
        print_color "${RED}" "     Fix errors listed above before retrying"
    fi

    echo ""
    print_color "${CYAN}" "  Log file: ${LOG_FILE}"
    echo ""
}

# Main validation flow
main() {
    parse_args "$@"

    print_color "${PURPLE}${BOLD}" "╔══════════════════════════════════════════════════════════════════╗"
    print_color "${PURPLE}${BOLD}" "║          Terraform Project Validator v1.0                        ║"
    print_color "${PURPLE}${BOLD}" "║          Pre-Flight Safety Check for Terraform Operations        ║"
    print_color "${PURPLE}${BOLD}" "╚══════════════════════════════════════════════════════════════════╝"

    log "START" "Validation started - Operation: ${OPERATION}, Expected Project: ${EXPECTED_PROJECT:-none}"

    # Audit log entry
    audit_log "VALIDATION" "status=START operation=${OPERATION} project=${EXPECTED_PROJECT:-NONE} terraform_dir=${TERRAFORM_DIR} var_file=${VAR_FILE:-NONE}"

    # Run validation checks
    check_gcloud || true
    check_gcp_project || true
    check_terraform || true
    check_terraform_directory || true
    check_terraform_init || true
    check_terraform_state || true
    check_variable_files || true
    check_destroy_safeguards || true

    # Generate summary
    generate_summary

    local confirmation_cancelled=false
    if [[ "${VALIDATION_PASSED}" == "true" ]] && [[ "${OPERATION}" == "destroy" ]]; then
        if ! require_confirmation; then
            confirmation_cancelled=true
            VALIDATION_PASSED=false
            ((VALIDATION_ERRORS++))
            print_color "${RED}" "  Destroy operation confirmation failed - aborting"
        fi
    fi

    log "END" "Validation completed - Passed: ${VALIDATION_PASSED}, Errors: ${VALIDATION_ERRORS}, Warnings: ${VALIDATION_WARNINGS}"

    # Audit log final status
    if [[ "${VALIDATION_PASSED}" == "true" ]]; then
        if [[ ${VALIDATION_WARNINGS} -eq 0 ]]; then
            audit_log "VALIDATION" "status=PASS operation=${OPERATION} project=${EXPECTED_PROJECT:-NONE} warnings=0 errors=0 var_file=${VAR_FILE:-NONE}"
        else
            audit_log "VALIDATION" "status=PASS_WITH_WARNINGS operation=${OPERATION} project=${EXPECTED_PROJECT:-NONE} warnings=${VALIDATION_WARNINGS} errors=0 var_file=${VAR_FILE:-NONE}"
        fi
    elif [[ "${confirmation_cancelled}" == "true" ]]; then
        audit_log "VALIDATION" "status=CANCELLED operation=${OPERATION} project=${EXPECTED_PROJECT:-NONE} warnings=${VALIDATION_WARNINGS} errors=${VALIDATION_ERRORS} var_file=${VAR_FILE:-NONE}"
    else
        audit_log "VALIDATION" "status=FAIL operation=${OPERATION} project=${EXPECTED_PROJECT:-NONE} warnings=${VALIDATION_WARNINGS} errors=${VALIDATION_ERRORS} var_file=${VAR_FILE:-NONE}"
    fi

    # Exit with appropriate code
    if [[ "${VALIDATION_PASSED}" == "true" ]]; then
        exit 0
    elif [[ "${confirmation_cancelled}" == "true" ]]; then
        exit 3
    else
        exit 1
    fi
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

main "$@"
