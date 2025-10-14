#!/bin/bash
#
# pre-destroy-validator.sh - Pre-Destroy Validation and Safety Gate
#
# Purpose: Comprehensive validation script specifically for terraform destroy operations
#          Implements multiple layers of verification before allowing destruction
#
# Author: DCG Infrastructure Team
# Version: 1.0.0
# Date: 2025-10-13
#
# Usage:
#   ./pre-destroy-validator.sh --project=PROJECT_ID [OPTIONS]
#
# Required Parameters:
#   --project=PROJECT_ID          Expected GCP project to destroy
#
# Optional Parameters:
#   --expected-resources=MIN-MAX  Expected resource count range (e.g., 80-110)
#   --var-file=PATH              Path to tfvars file (REQUIRED for safety)
#   --terraform-dir=PATH         Path to terraform directory (default: current dir)
#   --wrong-projects=LIST        Comma-separated list of projects to check for (default: other known projects)
#   --skip-backup               Skip state backup (NOT RECOMMENDED)
#   --non-interactive           Non-interactive mode (requires --confirm-destroy)
#   --confirm-destroy           Auto-confirm destruction (use with extreme caution)
#
# Exit Codes:
#   0 - Validation passed, safe to destroy
#   1 - Validation failed, DO NOT DESTROY
#   2 - Invalid arguments or configuration
#   3 - User cancelled operation
#
# Examples:
#   ./pre-destroy-validator.sh --project=cui-gitea-prod --expected-resources=80-110 --var-file=terraform.tfvars.prod
#   ./pre-destroy-validator.sh --project=dcg-gitea-stage --var-file=terraform.tfvars.staging
#
# Safety Features:
#   - Generates and analyzes terraform destroy plan
#   - Scans plan for wrong project names
#   - Validates resource count against expected range
#   - Creates state backup before destruction
#   - Requires double confirmation (project ID + "DESTROY")
#   - Generates destruction intent manifest
#   - Color-coded output for easy scanning
#

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EVIDENCE_DIR="${SCRIPT_DIR}/../.evidence/pre-destroy"
LOG_FILE="${EVIDENCE_DIR}/pre-destroy-validation-${TIMESTAMP}.log"
AUDIT_LOG="${PROJECT_ROOT}/logs/environment-audit.log"

# Default values
TERRAFORM_DIR="$(pwd)"
EXPECTED_PROJECT=""
EXPECTED_RESOURCES_MIN=0
EXPECTED_RESOURCES_MAX=999999
VAR_FILE=""
WRONG_PROJECTS=""
SKIP_BACKUP=false
NON_INTERACTIVE=false
CONFIRM_DESTROY=false

# Known projects that should NOT be destroyed by accident
KNOWN_PROJECTS=(
    "dcg-gitea-stage"
    "cui-gitea-prod"
    "dcg-gitea-dev"
)

# Terraform plan file
DESTROY_PLAN_FILE="destroy-validation.tfplan"
DESTROY_PLAN_TEXT="${EVIDENCE_DIR}/destroy-plan-${TIMESTAMP}.txt"
DESTROY_MANIFEST="${EVIDENCE_DIR}/destroy-intent-${TIMESTAMP}.json"

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

print_header() {
    echo ""
    print_color "${BOLD}${CYAN}" "═══════════════════════════════════════════════════════════════════"
    print_color "${BOLD}${CYAN}" "  $*"
    print_color "${BOLD}${CYAN}" "═══════════════════════════════════════════════════════════════════"
    echo ""
}

print_section() {
    echo ""
    print_color "${BOLD}${BLUE}" "▶ $*"
}

print_check() {
    local status=$1
    local message=$2
    case ${status} in
        PASS)
            print_color "${GREEN}" "  ✅ ${message}"
            ;;
        FAIL)
            print_color "${RED}" "  ❌ ${message}"
            ;;
        WARN)
            print_color "${YELLOW}" "  ⚠️  ${message}"
            ;;
        INFO)
            print_color "${CYAN}" "  ℹ️  ${message}"
            ;;
    esac
}

print_error() {
    print_color "${RED}" "❌ ERROR: $*" >&2
}

print_success() {
    print_color "${GREEN}" "✅ $*"
}

print_warning() {
    print_color "${YELLOW}" "⚠️  WARNING: $*"
}

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
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

fatal_error() {
    print_error "$*"
    log_message "FATAL ERROR: $*"
    exit 1
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

usage() {
    cat << EOF
Usage: $0 --project=PROJECT_ID [OPTIONS]

Pre-Destroy Validation and Safety Gate for Terraform Infrastructure

Required Parameters:
  --project=PROJECT_ID          Expected GCP project to destroy

Optional Parameters:
  --expected-resources=MIN-MAX  Expected resource count range (e.g., 80-110)
  --var-file=PATH              Path to tfvars file (REQUIRED for safety)
  --terraform-dir=PATH         Path to terraform directory (default: current dir)
  --wrong-projects=LIST        Comma-separated list of projects to check for
  --skip-backup               Skip state backup (NOT RECOMMENDED)
  --non-interactive           Non-interactive mode (requires --confirm-destroy)
  --confirm-destroy           Auto-confirm destruction (use with extreme caution)
  --help                      Show this help message

Examples:
  $0 --project=cui-gitea-prod --expected-resources=80-110 --var-file=terraform.tfvars.prod
  $0 --project=dcg-gitea-stage --var-file=terraform.tfvars.staging

Exit Codes:
  0 - Validation passed, safe to destroy
  1 - Validation failed, DO NOT DESTROY
  2 - Invalid arguments or configuration
  3 - User cancelled operation

EOF
}

parse_arguments() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 2
    fi

    for arg in "$@"; do
        case ${arg} in
            --project=*)
                EXPECTED_PROJECT="${arg#*=}"
                ;;
            --expected-resources=*)
                local range="${arg#*=}"
                if [[ ${range} =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    EXPECTED_RESOURCES_MIN="${BASH_REMATCH[1]}"
                    EXPECTED_RESOURCES_MAX="${BASH_REMATCH[2]}"
                else
                    fatal_error "Invalid resource range format. Use: MIN-MAX (e.g., 80-110)"
                fi
                ;;
            --var-file=*)
                VAR_FILE="${arg#*=}"
                ;;
            --terraform-dir=*)
                TERRAFORM_DIR="${arg#*=}"
                ;;
            --wrong-projects=*)
                WRONG_PROJECTS="${arg#*=}"
                ;;
            --skip-backup)
                SKIP_BACKUP=true
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                ;;
            --confirm-destroy)
                CONFIRM_DESTROY=true
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown argument: ${arg}"
                usage
                exit 2
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${EXPECTED_PROJECT}" ]]; then
        fatal_error "Missing required parameter: --project"
    fi

    # Build wrong projects list
    if [[ -z "${WRONG_PROJECTS}" ]]; then
        for proj in "${KNOWN_PROJECTS[@]}"; do
            if [[ "${proj}" != "${EXPECTED_PROJECT}" ]]; then
                if [[ -z "${WRONG_PROJECTS}" ]]; then
                    WRONG_PROJECTS="${proj}"
                else
                    WRONG_PROJECTS="${WRONG_PROJECTS},${proj}"
                fi
            fi
        done
    fi
}

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

validate_prerequisites() {
    print_section "Validating Prerequisites"

    # Check terraform
    if ! command -v terraform &> /dev/null; then
        print_check "FAIL" "Terraform not installed"
        return 1
    fi
    print_check "PASS" "Terraform installed: $(terraform version -json | jq -r '.terraform_version')"

    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        print_check "FAIL" "gcloud CLI not installed"
        return 1
    fi
    print_check "PASS" "gcloud CLI installed"

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_check "WARN" "jq not installed (optional, for JSON parsing)"
    else
        print_check "PASS" "jq installed"
    fi

    # Check terraform directory
    if [[ ! -d "${TERRAFORM_DIR}" ]]; then
        print_check "FAIL" "Terraform directory does not exist: ${TERRAFORM_DIR}"
        return 1
    fi
    print_check "PASS" "Terraform directory exists: ${TERRAFORM_DIR}"

    # Create evidence directory
    mkdir -p "${EVIDENCE_DIR}"
    print_check "PASS" "Evidence directory: ${EVIDENCE_DIR}"

    return 0
}

validate_gcp_context() {
    print_section "Validating GCP Project Context"

    local gcloud_project
    gcloud_project=$(gcloud config get-value project 2>/dev/null || echo "")

    if [[ -z "${gcloud_project}" ]]; then
        print_check "WARN" "No active GCP project in gcloud config"
        print_color "${YELLOW}" "      Run: gcloud config set project ${EXPECTED_PROJECT}"
    elif [[ "${gcloud_project}" == "${EXPECTED_PROJECT}" ]]; then
        print_check "PASS" "GCloud project matches expected: ${EXPECTED_PROJECT}"
    else
        print_check "FAIL" "GCloud project mismatch!"
        print_color "${RED}" "      Expected: ${EXPECTED_PROJECT}"
        print_color "${RED}" "      Current:  ${gcloud_project}"
        print_color "${YELLOW}" "      Run: gcloud config set project ${EXPECTED_PROJECT}"
        return 1
    fi

    return 0
}

validate_terraform_state() {
    print_section "Validating Terraform State"

    cd "${TERRAFORM_DIR}"

    # Check terraform initialized
    if [[ ! -d ".terraform" ]]; then
        print_check "FAIL" "Terraform not initialized"
        print_color "${YELLOW}" "      Run: terraform init"
        return 1
    fi
    print_check "PASS" "Terraform initialized"

    # Check state exists
    if ! terraform state list &> /dev/null; then
        print_check "WARN" "No resources in state (empty state)"
        return 0
    fi

    local resource_count
    resource_count=$(terraform state list 2>/dev/null | wc -l)
    print_check "INFO" "Current state contains ${resource_count} resources"

    # Validate state contains expected project
    local state_content
    state_content=$(terraform state pull 2>/dev/null || echo "{}")

    if echo "${state_content}" | grep -q "\"${EXPECTED_PROJECT}\""; then
        print_check "PASS" "State contains expected project: ${EXPECTED_PROJECT}"
    else
        print_check "FAIL" "State does NOT contain expected project: ${EXPECTED_PROJECT}"
        return 1
    fi

    # Check for wrong project names in state
    local found_wrong=false
    IFS=',' read -ra WRONG_PROJ_ARRAY <<< "${WRONG_PROJECTS}"
    for wrong_proj in "${WRONG_PROJ_ARRAY[@]}"; do
        if echo "${state_content}" | grep -q "\"${wrong_proj}\""; then
            print_check "FAIL" "State contains WRONG project: ${wrong_proj}"
            found_wrong=true
        fi
    done

    if [[ "${found_wrong}" == "true" ]]; then
        return 1
    fi

    return 0
}

validate_variable_file() {
    print_section "Validating Variable File Configuration"

    # Check if var-file specified
    if [[ -z "${VAR_FILE}" ]]; then
        print_check "WARN" "No --var-file specified (will use auto-loaded terraform.tfvars)"
        print_color "${YELLOW}" "      ⚠️  This is a common cause of wrong project destruction!"
        print_color "${YELLOW}" "      ⚠️  HIGHLY RECOMMENDED to use explicit --var-file"

        # Check if terraform.tfvars exists
        if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
            print_check "WARN" "terraform.tfvars exists and will be auto-loaded"
            local tfvars_project
            tfvars_project=$(grep 'project_id' "${TERRAFORM_DIR}/terraform.tfvars" | cut -d'"' -f2 || echo "")
            if [[ -n "${tfvars_project}" ]]; then
                if [[ "${tfvars_project}" == "${EXPECTED_PROJECT}" ]]; then
                    print_check "INFO" "terraform.tfvars project_id: ${tfvars_project} (matches expected)"
                else
                    print_check "FAIL" "terraform.tfvars project_id: ${tfvars_project} (DOES NOT MATCH)"
                    print_color "${RED}" "      Expected: ${EXPECTED_PROJECT}"
                    print_color "${RED}" "      Found:    ${tfvars_project}"
                    return 1
                fi
            fi
        fi
    else
        # Validate var-file exists
        if [[ ! -f "${TERRAFORM_DIR}/${VAR_FILE}" ]]; then
            print_check "FAIL" "Variable file does not exist: ${VAR_FILE}"
            return 1
        fi
        print_check "PASS" "Variable file exists: ${VAR_FILE}"

        # Validate var-file contains expected project
        local varfile_project
        varfile_project=$(grep 'project_id' "${TERRAFORM_DIR}/${VAR_FILE}" | cut -d'"' -f2 || echo "")
        if [[ -z "${varfile_project}" ]]; then
            print_check "WARN" "Cannot find project_id in ${VAR_FILE}"
        elif [[ "${varfile_project}" == "${EXPECTED_PROJECT}" ]]; then
            print_check "PASS" "Variable file project_id: ${varfile_project} (matches expected)"
        else
            print_check "FAIL" "Variable file project_id mismatch!"
            print_color "${RED}" "      Expected: ${EXPECTED_PROJECT}"
            print_color "${RED}" "      Found:    ${varfile_project}"
            return 1
        fi
    fi

    return 0
}

generate_destroy_plan() {
    print_section "Generating Terraform Destroy Plan"

    cd "${TERRAFORM_DIR}"

    print_color "${CYAN}" "  Running: terraform plan -destroy..."

    local plan_cmd="terraform plan -destroy -out=${DESTROY_PLAN_FILE}"
    if [[ -n "${VAR_FILE}" ]]; then
        plan_cmd="${plan_cmd} -var-file=${VAR_FILE}"
    fi

    print_color "${CYAN}" "  Command: ${plan_cmd}"

    if ${plan_cmd} > "${DESTROY_PLAN_TEXT}" 2>&1; then
        print_check "PASS" "Destroy plan generated successfully"
    else
        print_check "FAIL" "Failed to generate destroy plan"
        print_color "${RED}" "  See: ${DESTROY_PLAN_TEXT}"
        return 1
    fi

    # Also save human-readable plan
    terraform show "${DESTROY_PLAN_FILE}" > "${DESTROY_PLAN_TEXT}" 2>&1 || true

    return 0
}

analyze_destroy_plan() {
    print_section "Analyzing Destroy Plan"

    if [[ ! -f "${DESTROY_PLAN_TEXT}" ]]; then
        print_check "FAIL" "Destroy plan text file not found"
        return 1
    fi

    # Count resources to be destroyed
    local destroy_count
    destroy_count=$(grep -c "will be destroyed" "${DESTROY_PLAN_TEXT}" || echo "0")

    print_check "INFO" "Resources to be destroyed: ${destroy_count}"

    # Validate resource count range
    if [[ ${EXPECTED_RESOURCES_MIN} -gt 0 ]] || [[ ${EXPECTED_RESOURCES_MAX} -lt 999999 ]]; then
        if [[ ${destroy_count} -ge ${EXPECTED_RESOURCES_MIN} ]] && [[ ${destroy_count} -le ${EXPECTED_RESOURCES_MAX} ]]; then
            print_check "PASS" "Resource count within expected range: ${EXPECTED_RESOURCES_MIN}-${EXPECTED_RESOURCES_MAX}"
        else
            print_check "FAIL" "Resource count OUTSIDE expected range!"
            print_color "${RED}" "      Expected: ${EXPECTED_RESOURCES_MIN}-${EXPECTED_RESOURCES_MAX}"
            print_color "${RED}" "      Found:    ${destroy_count}"
            return 1
        fi
    fi

    # Check for expected project name
    local expected_count
    expected_count=$(grep -c "${EXPECTED_PROJECT}" "${DESTROY_PLAN_TEXT}" || echo "0")
    if [[ ${expected_count} -gt 0 ]]; then
        print_check "PASS" "Expected project name found in plan: ${EXPECTED_PROJECT} (${expected_count} occurrences)"
    else
        print_check "FAIL" "Expected project name NOT found in plan: ${EXPECTED_PROJECT}"
        return 1
    fi

    # Check for wrong project names
    local found_wrong=false
    IFS=',' read -ra WRONG_PROJ_ARRAY <<< "${WRONG_PROJECTS}"
    for wrong_proj in "${WRONG_PROJ_ARRAY[@]}"; do
        local wrong_count
        wrong_count=$(grep -c "${wrong_proj}" "${DESTROY_PLAN_TEXT}" || echo "0")
        if [[ ${wrong_count} -gt 0 ]]; then
            print_check "FAIL" "WRONG project name found in plan: ${wrong_proj} (${wrong_count} occurrences)"
            found_wrong=true
        fi
    done

    if [[ "${found_wrong}" == "true" ]]; then
        print_color "${RED}" "  ⚠️  CRITICAL: Plan contains resources from WRONG project(s)!"
        print_color "${RED}" "  ⚠️  DO NOT PROCEED WITH DESTRUCTION!"
        return 1
    fi

    print_check "PASS" "No wrong project names found in plan"

    return 0
}

display_resource_summary() {
    print_section "Resource Summary"

    if [[ ! -f "${DESTROY_PLAN_TEXT}" ]]; then
        print_check "WARN" "Cannot display summary - plan file not found"
        return 0
    fi

    print_color "${CYAN}" "Resources to be destroyed:"
    echo ""

    # Extract and display resource types
    grep "will be destroyed" "${DESTROY_PLAN_TEXT}" | \
        sed 's/.*# //' | \
        sed 's/ will be destroyed.*//' | \
        sort | \
        uniq -c | \
        awk '{printf "  %-5s %s\n", $1, $2}' | \
        while read -r line; do
            print_color "${YELLOW}" "  ${line}"
        done

    echo ""
    print_color "${CYAN}" "Full plan details: ${DESTROY_PLAN_TEXT}"
}

backup_terraform_state() {
    if [[ "${SKIP_BACKUP}" == "true" ]]; then
        print_section "Skipping State Backup (--skip-backup specified)"
        print_warning "State backup skipped - NO ROLLBACK POSSIBLE if destruction fails"
        return 0
    fi

    print_section "Backing Up Terraform State"

    cd "${TERRAFORM_DIR}"

    local backup_file="${EVIDENCE_DIR}/terraform-state-backup-${TIMESTAMP}.json"

    if terraform state pull > "${backup_file}" 2>/dev/null; then
        local backup_size
        backup_size=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}" 2>/dev/null || echo "0")
        print_check "PASS" "State backed up: ${backup_file} (${backup_size} bytes)"

        # Generate SHA256 checksum
        if command -v sha256sum &> /dev/null; then
            local checksum
            checksum=$(sha256sum "${backup_file}" | awk '{print $1}')
            echo "${checksum}  ${backup_file}" > "${backup_file}.sha256"
            print_check "INFO" "SHA256: ${checksum}"
        fi
    else
        print_check "WARN" "Failed to backup state (may be empty)"
    fi

    return 0
}

generate_destroy_manifest() {
    print_section "Generating Destruction Intent Manifest"

    local manifest_data
    manifest_data=$(cat <<EOF
{
  "destruction_intent": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "operator": "${USER}",
    "hostname": "$(hostname)",
    "project": "${EXPECTED_PROJECT}",
    "terraform_dir": "${TERRAFORM_DIR}",
    "var_file": "${VAR_FILE:-auto-loaded}",
    "expected_resources": {
      "min": ${EXPECTED_RESOURCES_MIN},
      "max": ${EXPECTED_RESOURCES_MAX}
    },
    "validation_results": {
      "gcp_context": "validated",
      "terraform_state": "validated",
      "variable_file": "validated",
      "destroy_plan": "validated",
      "resource_count": $(grep -c "will be destroyed" "${DESTROY_PLAN_TEXT}" || echo "0")
    },
    "artifacts": {
      "destroy_plan": "${DESTROY_PLAN_FILE}",
      "plan_text": "${DESTROY_PLAN_TEXT}",
      "state_backup": "${EVIDENCE_DIR}/terraform-state-backup-${TIMESTAMP}.json",
      "validation_log": "${LOG_FILE}"
    },
    "compliance": {
      "framework": "CMMC 2.0 Level 2",
      "controls": ["CM.L2-3.4.9", "MA.L2-3.7.5"],
      "evidence_retention": "7 years"
    }
  }
}
EOF
)

    echo "${manifest_data}" > "${DESTROY_MANIFEST}"
    print_check "PASS" "Manifest generated: ${DESTROY_MANIFEST}"

    return 0
}

require_confirmation() {
    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        if [[ "${CONFIRM_DESTROY}" == "true" ]]; then
            print_section "Non-Interactive Mode - Auto-Confirming"
            print_warning "Auto-confirmation enabled - destruction will proceed"
            return 0
        else
            print_error "Non-interactive mode requires --confirm-destroy flag"
            return 1
        fi
    fi

    print_header "⚠️  FINAL CONFIRMATION REQUIRED ⚠️"

    print_color "${RED}" "  You are about to DESTROY infrastructure in:"
    print_color "${BOLD}${RED}" "    PROJECT: ${EXPECTED_PROJECT}"
    echo ""
    print_color "${YELLOW}" "  Resources to be destroyed: $(grep -c "will be destroyed" "${DESTROY_PLAN_TEXT}" || echo "0")"
    echo ""
    print_color "${RED}" "  This action is IRREVERSIBLE!"
    echo ""

    # First confirmation: type project ID
    print_color "${CYAN}" "  Step 1 of 2: Type the project ID to confirm"
    echo -n "  Enter project ID: "
    read -r confirm_project

    if [[ "${confirm_project}" != "${EXPECTED_PROJECT}" ]]; then
        print_error "Project ID mismatch - destruction cancelled"
        return 1
    fi
    print_check "PASS" "Project ID confirmed"

    echo ""

    # Second confirmation: type DESTROY
    print_color "${CYAN}" "  Step 2 of 2: Type 'DESTROY' to proceed (all capitals)"
    echo -n "  Enter DESTROY: "
    read -r confirm_destroy

    if [[ "${confirm_destroy}" != "DESTROY" ]]; then
        print_error "Confirmation failed - destruction cancelled"
        return 1
    fi
    print_check "PASS" "Destruction confirmed"

    echo ""
    print_color "${GREEN}" "  Double confirmation received - destruction authorized"

    return 0
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    print_header "Pre-Destroy Validation and Safety Gate"

    print_color "${CYAN}" "Script Version: 1.0.0"
    print_color "${CYAN}" "Timestamp: $(date)"
    print_color "${CYAN}" "Operator: ${USER}"
    echo ""

    # Parse arguments
    parse_arguments "$@"

    log_message "Starting pre-destroy validation for project: ${EXPECTED_PROJECT}"

    # Audit log entry
    audit_log "VALIDATION" "status=START context=pre-destroy project=${EXPECTED_PROJECT} terraform_dir=${TERRAFORM_DIR} var_file=${VAR_FILE:-auto-loaded}"

    # Initialize validation status
    local validation_failed=false

    # Run validation checks
    if ! validate_prerequisites; then
        validation_failed=true
    fi

    if ! validate_gcp_context; then
        validation_failed=true
    fi

    if ! validate_terraform_state; then
        validation_failed=true
    fi

    if ! validate_variable_file; then
        validation_failed=true
    fi

    # Stop if basic validation failed
    if [[ "${validation_failed}" == "true" ]]; then
        print_header "❌ VALIDATION FAILED"
        print_error "One or more validation checks failed"
        print_error "DO NOT PROCEED WITH DESTRUCTION"
        log_message "Validation failed - destruction blocked"
        audit_log "VALIDATION" "status=FAILED context=pre-destroy project=${EXPECTED_PROJECT} var_file=${VAR_FILE:-auto-loaded}"
        exit 1
    fi

    # Generate and analyze destroy plan
    if ! generate_destroy_plan; then
        print_header "❌ PLAN GENERATION FAILED"
        print_error "Failed to generate destroy plan"
        log_message "Plan generation failed"
        audit_log "VALIDATION" "status=PLAN_GENERATION_FAILED context=pre-destroy project=${EXPECTED_PROJECT} var_file=${VAR_FILE:-auto-loaded}"
        exit 1
    fi

    if ! analyze_destroy_plan; then
        print_header "❌ PLAN ANALYSIS FAILED"
        print_error "Destroy plan analysis detected issues"
        print_error "DO NOT PROCEED WITH DESTRUCTION"
        log_message "Plan analysis failed - destruction blocked"
        audit_log "VALIDATION" "status=PLAN_ANALYSIS_FAILED context=pre-destroy project=${EXPECTED_PROJECT} var_file=${VAR_FILE:-auto-loaded}"
        exit 1
    fi

    # Display resource summary
    display_resource_summary

    # Backup state
    if ! backup_terraform_state; then
        print_warning "State backup failed - proceeding anyway"
    fi

    # Generate manifest
    generate_destroy_manifest

    # All validation passed
    print_header "✅ ALL VALIDATIONS PASSED"
    print_success "Project: ${EXPECTED_PROJECT}"
    print_success "Resources to destroy: $(grep -c "will be destroyed" "${DESTROY_PLAN_TEXT}" || echo "0")"
    print_success "Destroy plan: ${DESTROY_PLAN_FILE}"
    print_success "State backup: ${EVIDENCE_DIR}/terraform-state-backup-${TIMESTAMP}.json"
    echo ""

    # Require confirmation
    if ! require_confirmation; then
        print_header "❌ DESTRUCTION CANCELLED"
        print_color "${YELLOW}" "User cancelled operation - no resources were destroyed"
        log_message "Destruction cancelled by user"
        local resource_count
        resource_count=$(grep -c "will be destroyed" "${DESTROY_PLAN_TEXT}" || echo "0")
        audit_log "VALIDATION" "status=CANCELLED context=pre-destroy project=${EXPECTED_PROJECT} resources=${resource_count} var_file=${VAR_FILE:-auto-loaded}"
        exit 3
    fi

    # Final authorization
    print_header "✅ DESTRUCTION AUTHORIZED"
    print_success "All validation checks passed"
    print_success "Double confirmation received"
    print_success "Safe to proceed with destruction"
    echo ""
    print_color "${GREEN}" "Execute destruction with:"
    print_color "${BOLD}${GREEN}" "  terraform apply ${DESTROY_PLAN_FILE}"
    echo ""
    print_color "${CYAN}" "Evidence artifacts:"
    print_color "${CYAN}" "  - Destroy plan: ${DESTROY_PLAN_FILE}"
    print_color "${CYAN}" "  - Plan details: ${DESTROY_PLAN_TEXT}"
    print_color "${CYAN}" "  - State backup: ${EVIDENCE_DIR}/terraform-state-backup-${TIMESTAMP}.json"
    print_color "${CYAN}" "  - Manifest: ${DESTROY_MANIFEST}"
    print_color "${CYAN}" "  - Validation log: ${LOG_FILE}"

    log_message "Validation completed successfully - destruction authorized"

    # Audit log final status
    local resource_count
    resource_count=$(grep -c "will be destroyed" "${DESTROY_PLAN_TEXT}" || echo "0")
    audit_log "VALIDATION" "status=AUTHORIZED context=pre-destroy project=${EXPECTED_PROJECT} resources=${resource_count} var_file=${VAR_FILE:-auto-loaded}"

    exit 0
}

# Run main function with all arguments
main "$@"
