#!/bin/bash
# ==============================================================================
# GCP Gitea Deployment Orchestration Script
# CMMC Level 2 / NIST SP 800-171 Compliant
# ==============================================================================
#
# Usage: ./gcp-deploy.sh [options]
#   -p PROJECT_ID    GCP Project ID (required)
#   -r REGION        GCP Region (default: us-central1)
#   -e ENVIRONMENT   Environment: dev|staging|prod (default: prod)
#   -d DOMAIN        Gitea domain name (required)
#   -a ADMIN_EMAIL   Admin email address (required)
#   -t TFVARS_FILE   Path to terraform.tfvars file (optional)
#   -s               Skip confirmation prompts
#   -v               Verbose output
#   -h               Show this help message
#
# Examples:
#   ./gcp-deploy.sh -p my-project -d git.example.com -a admin@example.com
#   ./gcp-deploy.sh -p my-project -d git.example.com -a admin@example.com -t prod.tfvars
#
# Exit Codes:
#   0 - Success
#   1 - Error
#   2 - Warning/Partial failure
#
# CMMC Controls Addressed:
#   - AC.L2-3.1.1: Authorized Access Control
#   - AU.L2-3.3.1: Event Logging
#   - CM.L2-3.4.2: System Baseline Configuration
#   - SC.L2-3.13.11: Cryptographic Protection
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TERRAFORM_DIR="${PROJECT_ROOT}/terraform/gcp-gitea"
readonly EVIDENCE_DIR="${TERRAFORM_DIR}/evidence"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${LOG_DIR}/deployment_${TIMESTAMP}.log"
readonly EVIDENCE_FILE="${EVIDENCE_DIR}/deployment_${TIMESTAMP}.json"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Default values
ENVIRONMENT="prod"
REGION="us-central1"
ZONE=""
SKIP_CONFIRM=false
VERBOSE=false
TFVARS_FILE=""
PROJECT_ID=""
DOMAIN=""
ADMIN_EMAIL=""

# Deployment state tracking
DEPLOYMENT_STATUS="PENDING"
DEPLOYMENT_START=""
DEPLOYMENT_END=""
TERRAFORM_INITIALIZED=false
TERRAFORM_APPLIED=false
INSTANCE_READY=false
GITEA_ACCESSIBLE=false

# ==============================================================================
# FUNCTIONS
# ==============================================================================

# Print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Log message to file and optionally stdout
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

# Show usage information
show_help() {
    grep "^#" "$0" | head -35 | tail -33 | sed 's/^# //' | sed 's/^#//'
}

# Parse command line arguments
parse_args() {
    while getopts "p:r:e:d:a:t:svh" opt; do
        case ${opt} in
            p)
                PROJECT_ID="${OPTARG}"
                ;;
            r)
                REGION="${OPTARG}"
                ;;
            e)
                ENVIRONMENT="${OPTARG}"
                ;;
            d)
                DOMAIN="${OPTARG}"
                ;;
            a)
                ADMIN_EMAIL="${OPTARG}"
                ;;
            t)
                TFVARS_FILE="${OPTARG}"
                ;;
            s)
                SKIP_CONFIRM=true
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

# Validate required parameters
validate_params() {
    local errors=0

    if [[ -z "${PROJECT_ID}" ]]; then
        log ERROR "Project ID is required (-p)"
        ((errors++))
    fi

    if [[ -z "${DOMAIN}" ]]; then
        log ERROR "Domain name is required (-d)"
        ((errors++))
    fi

    if [[ -z "${ADMIN_EMAIL}" ]]; then
        log ERROR "Admin email is required (-a)"
        ((errors++))
    fi

    if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
        log ERROR "Invalid environment: ${ENVIRONMENT}. Must be dev, staging, or prod"
        ((errors++))
    fi

    if [[ -n "${TFVARS_FILE}" && ! -f "${TFVARS_FILE}" ]]; then
        log ERROR "Terraform variables file not found: ${TFVARS_FILE}"
        ((errors++))
    fi

    if [[ ${errors} -gt 0 ]]; then
        log ERROR "Parameter validation failed with ${errors} error(s)"
        exit 1
    fi

    # Set zone based on region
    ZONE="${REGION}-a"
}

# Initialize directories
init_directories() {
    log INFO "Initializing directories..."

    mkdir -p "${LOG_DIR}"
    mkdir -p "${EVIDENCE_DIR}"

    # Create log file
    touch "${LOG_FILE}"

    log SUCCESS "Directories initialized"
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."

    local prereqs_met=true

    # Check for required commands
    local required_commands=("gcloud" "terraform" "jq" "curl")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            log ERROR "Required command not found: ${cmd}"
            prereqs_met=false
        else
            log DEBUG "${cmd} found: $(which ${cmd})"
        fi
    done

    # Check gcloud configuration
    if command -v gcloud &> /dev/null; then
        local current_project
        current_project=$(gcloud config get-value project 2>/dev/null || echo "")

        if [[ -z "${current_project}" ]]; then
            log WARNING "No default GCP project configured"
        elif [[ "${current_project}" != "${PROJECT_ID}" ]]; then
            log INFO "Switching GCP project from ${current_project} to ${PROJECT_ID}"
            gcloud config set project "${PROJECT_ID}" 2>&1 | tee -a "${LOG_FILE}"
        fi

        # Check authentication
        if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
            log ERROR "Not authenticated to GCP. Run: gcloud auth login"
            prereqs_met=false
        fi
    fi

    # Check Terraform version
    if command -v terraform &> /dev/null; then
        local tf_version
        tf_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
        log DEBUG "Terraform version: ${tf_version}"

        # Check for minimum version (1.0.0)
        if [[ "${tf_version}" != "unknown" ]]; then
            local min_version="1.0.0"
            if [[ "$(printf '%s\n' "${min_version}" "${tf_version}" | sort -V | head -n1)" != "${min_version}" ]]; then
                log ERROR "Terraform version ${tf_version} is too old. Minimum required: ${min_version}"
                prereqs_met=false
            fi
        fi
    fi

    if [[ "${prereqs_met}" == "false" ]]; then
        log ERROR "Prerequisites check failed"
        exit 1
    fi

    log SUCCESS "All prerequisites met"
}

# Check GCP permissions
check_gcp_permissions() {
    log INFO "Checking GCP permissions for project ${PROJECT_ID}..."

    local required_roles=(
        "roles/compute.admin"
        "roles/iam.serviceAccountAdmin"
        "roles/storage.admin"
    )

    local user_email
    user_email=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)

    for role in "${required_roles[@]}"; do
        log DEBUG "Checking role: ${role}"

        # This is a simplified check - in production, use proper IAM policy checking
        if ! gcloud projects get-iam-policy "${PROJECT_ID}" --format=json 2>/dev/null | \
           jq -r ".bindings[] | select(.role == \"${role}\") | .members[]" | \
           grep -q "${user_email}"; then
            log WARNING "User may not have required role: ${role}"
        fi
    done

    log SUCCESS "Permission check completed"
}

# Enable required GCP APIs
enable_apis() {
    log INFO "Enabling required GCP APIs..."

    local required_apis=(
        "compute.googleapis.com"
        "storage-api.googleapis.com"
        "cloudkms.googleapis.com"
        "secretmanager.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )

    for api in "${required_apis[@]}"; do
        log DEBUG "Checking API: ${api}"

        if gcloud services list --enabled --filter="name:${api}" --format="value(name)" 2>/dev/null | grep -q "${api}"; then
            log DEBUG "API already enabled: ${api}"
        else
            log INFO "Enabling API: ${api}"
            gcloud services enable "${api}" --project="${PROJECT_ID}" 2>&1 | tee -a "${LOG_FILE}"
        fi
    done

    log SUCCESS "All required APIs enabled"
}

# Generate terraform.tfvars if not provided
generate_tfvars() {
    if [[ -n "${TFVARS_FILE}" ]]; then
        log INFO "Using provided terraform.tfvars: ${TFVARS_FILE}"
        cp "${TFVARS_FILE}" "${TERRAFORM_DIR}/terraform.tfvars"
    else
        log INFO "Generating terraform.tfvars..."

        cat > "${TERRAFORM_DIR}/terraform.tfvars" <<EOF
# Auto-generated Terraform variables
# Generated: $(date -Iseconds)
# Environment: ${ENVIRONMENT}

project_id              = "${PROJECT_ID}"
region                  = "${REGION}"
zone                    = "${ZONE}"
environment             = "${ENVIRONMENT}"
gitea_domain            = "${DOMAIN}"
gitea_admin_email       = "${ADMIN_EMAIL}"
alert_email             = "${ADMIN_EMAIL}"

# Security settings (CMMC Level 2 compliant)
enable_secure_boot              = true
enable_vtpm                     = true
enable_integrity_monitoring     = true
enable_os_login                 = true
enable_iap                      = true
enable_kms                      = true
enable_secret_manager           = true
enable_cloud_armor              = true
enable_shielded_vm              = true

# Monitoring and backup
enable_monitoring               = true
enable_uptime_checks            = true
enable_automated_backups        = true
enable_cross_region_backup      = false

# Storage retention (CMMC requires 7 years for evidence)
evidence_retention_days         = 2555
backup_retention_days           = 30
logs_retention_days             = 90

# Network security
allowed_ssh_cidr_ranges         = ["35.235.240.0/20"]  # IAP only
allowed_https_cidr_ranges       = ["0.0.0.0/0"]        # Public HTTPS
allowed_git_ssh_cidr_ranges     = []                   # Configure as needed

# Instance configuration
machine_type            = "${ENVIRONMENT == "prod" ? "e2-standard-8" : "e2-standard-4"}"
boot_disk_size          = ${ENVIRONMENT == "prod" ? "200" : "100"}
data_disk_size          = ${ENVIRONMENT == "prod" ? "500" : "200"}
boot_disk_type          = "pd-ssd"
data_disk_type          = "pd-ssd"

# Gitea configuration
gitea_disable_registration      = true
gitea_require_signin_view       = false

# Labels
additional_labels = {
  managed_by  = "terraform"
  environment = "${ENVIRONMENT}"
  compliance  = "cmmc-level-2"
  created_by  = "deployment-script"
  created_at  = "${TIMESTAMP}"
}
EOF

        log SUCCESS "Generated terraform.tfvars"
        log DEBUG "Variables file location: ${TERRAFORM_DIR}/terraform.tfvars"
    fi
}

# Initialize Terraform
terraform_init() {
    log INFO "Initializing Terraform..."

    cd "${TERRAFORM_DIR}"

    if terraform init -upgrade 2>&1 | tee -a "${LOG_FILE}"; then
        TERRAFORM_INITIALIZED=true
        log SUCCESS "Terraform initialized"
    else
        log ERROR "Terraform initialization failed"
        exit 1
    fi
}

# Run Terraform plan
terraform_plan() {
    log INFO "Running Terraform plan..."

    cd "${TERRAFORM_DIR}"

    if terraform plan -out=tfplan 2>&1 | tee -a "${LOG_FILE}"; then
        log SUCCESS "Terraform plan completed"

        # Show resource summary
        log INFO "Resources to be created:"
        terraform show -json tfplan 2>/dev/null | \
            jq -r '.resource_changes[] | select(.change.actions[] == "create") | .address' | \
            while read -r resource; do
                log DEBUG "  - ${resource}"
            done
    else
        log ERROR "Terraform plan failed"
        exit 1
    fi
}

# Confirm deployment
confirm_deployment() {
    if [[ "${SKIP_CONFIRM}" == "true" ]]; then
        log INFO "Skipping confirmation (auto-confirm enabled)"
        return 0
    fi

    print_color "${YELLOW}" "
╔══════════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT CONFIRMATION                       ║
╠══════════════════════════════════════════════════════════════════╣
║ Project:      ${PROJECT_ID}
║ Region:       ${REGION}
║ Environment:  ${ENVIRONMENT}
║ Domain:       ${DOMAIN}
║ Admin Email:  ${ADMIN_EMAIL}
╚══════════════════════════════════════════════════════════════════╝
"

    read -p "Do you want to proceed with the deployment? (yes/no): " -r

    if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
        log WARNING "Deployment cancelled by user"
        exit 0
    fi
}

# Apply Terraform configuration
terraform_apply() {
    log INFO "Applying Terraform configuration..."

    DEPLOYMENT_START=$(date -Iseconds)
    DEPLOYMENT_STATUS="IN_PROGRESS"

    cd "${TERRAFORM_DIR}"

    if terraform apply tfplan 2>&1 | tee -a "${LOG_FILE}"; then
        TERRAFORM_APPLIED=true
        log SUCCESS "Terraform apply completed"
    else
        DEPLOYMENT_STATUS="FAILED"
        log ERROR "Terraform apply failed"
        generate_evidence "FAILED"
        exit 1
    fi
}

# Wait for instance to be ready
wait_for_instance() {
    log INFO "Waiting for instance to be ready..."

    local instance_name
    instance_name=$(terraform output -raw instance_name 2>/dev/null || echo "")

    if [[ -z "${instance_name}" ]]; then
        log ERROR "Could not get instance name from Terraform outputs"
        return 1
    fi

    local max_attempts=30
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        ((attempt++))
        log DEBUG "Checking instance status (attempt ${attempt}/${max_attempts})..."

        local status
        status=$(gcloud compute instances describe "${instance_name}" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}" \
            --format="value(status)" 2>/dev/null || echo "UNKNOWN")

        if [[ "${status}" == "RUNNING" ]]; then
            log SUCCESS "Instance is running"
            INSTANCE_READY=true

            # Wait for startup script to complete
            log INFO "Waiting for startup script to complete..."
            sleep 60

            # Check serial port output for completion
            local serial_output
            serial_output=$(gcloud compute instances get-serial-port-output \
                "${instance_name}" \
                --zone="${ZONE}" \
                --project="${PROJECT_ID}" 2>/dev/null | tail -20)

            if echo "${serial_output}" | grep -q "Startup script completed"; then
                log SUCCESS "Startup script completed"
                return 0
            fi
        fi

        sleep 10
    done

    log ERROR "Instance did not become ready in time"
    return 1
}

# Verify Gitea accessibility
verify_gitea() {
    log INFO "Verifying Gitea accessibility..."

    local gitea_url
    gitea_url=$(terraform output -raw gitea_url 2>/dev/null || echo "")

    if [[ -z "${gitea_url}" ]]; then
        log ERROR "Could not get Gitea URL from Terraform outputs"
        return 1
    fi

    local external_ip
    external_ip=$(terraform output -raw instance_external_ip 2>/dev/null || echo "")

    log INFO "Gitea URL: ${gitea_url}"
    log INFO "External IP: ${external_ip}"

    # Check if Gitea responds (may not have SSL yet)
    local max_attempts=20
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        ((attempt++))
        log DEBUG "Checking Gitea accessibility (attempt ${attempt}/${max_attempts})..."

        # Try both HTTPS and HTTP
        if curl -k -s -o /dev/null -w "%{http_code}" "https://${external_ip}" | grep -qE "^(200|302|303)$"; then
            log SUCCESS "Gitea is accessible via HTTPS"
            GITEA_ACCESSIBLE=true
            return 0
        elif curl -s -o /dev/null -w "%{http_code}" "http://${external_ip}:3000" | grep -qE "^(200|302|303)$"; then
            log SUCCESS "Gitea is accessible via HTTP (configure SSL certificate)"
            GITEA_ACCESSIBLE=true
            return 0
        fi

        sleep 15
    done

    log WARNING "Gitea is not yet accessible. This may be normal if DNS/SSL is not configured"
    return 2
}

# Display post-deployment information
display_post_deployment() {
    log INFO "Gathering deployment information..."

    cd "${TERRAFORM_DIR}"

    # Get outputs
    local instance_ip external_ip ssh_command gitea_url
    instance_ip=$(terraform output -raw instance_internal_ip 2>/dev/null || echo "N/A")
    external_ip=$(terraform output -raw instance_external_ip 2>/dev/null || echo "N/A")
    ssh_command=$(terraform output -raw ssh_command 2>/dev/null || echo "N/A")
    gitea_url=$(terraform output -raw gitea_url 2>/dev/null || echo "N/A")

    local admin_username admin_password_secret secrets_enabled
    admin_username=$(terraform output -raw gitea_admin_username 2>/dev/null || echo "admin")
    admin_password_secret=$(terraform output -raw admin_password_secret_name 2>/dev/null || echo "gitea-admin-password")

    # Parse boolean output properly - terraform output -raw doesn't work with booleans
    # Use -json and jq, or fall back to checking for "true" string
    if command -v jq &> /dev/null; then
        secrets_enabled=$(terraform output -json secret_manager_enabled 2>/dev/null | jq -r '.' 2>/dev/null || echo "true")
    else
        # Fallback: use plain output and check for "true" string
        secrets_enabled=$(terraform output secret_manager_enabled 2>/dev/null | grep -oE "true|false" || echo "true")
    fi

    # Get bucket names
    local evidence_bucket backup_bucket logs_bucket
    evidence_bucket=$(terraform output -raw evidence_bucket_name 2>/dev/null || echo "N/A")
    backup_bucket=$(terraform output -raw backup_bucket_name 2>/dev/null || echo "N/A")
    logs_bucket=$(terraform output -raw logs_bucket_name 2>/dev/null || echo "N/A")

    # Get service accounts
    local gitea_sa evidence_sa backup_sa
    gitea_sa=$(terraform output -raw gitea_service_account_email 2>/dev/null || echo "N/A")
    evidence_sa=$(terraform output -raw evidence_service_account_email 2>/dev/null || echo "N/A")
    backup_sa=$(terraform output -raw backup_service_account_email 2>/dev/null || echo "N/A")

    local password_line
    if [[ "${secrets_enabled}" == "true" ]]; then
        password_line="Admin Password:   gcloud secrets versions access latest --secret=${admin_password_secret} --project=${PROJECT_ID}"
    else
        password_line="Admin Password:   ChangeMe!123456 (Secret Manager disabled)"
    fi

    local summary
    summary=$(cat <<EOF
╔══════════════════════════════════════════════════════════════════╗
║                   DEPLOYMENT SUCCESSFUL                          ║
╚══════════════════════════════════════════════════════════════════╝

📍 ACCESS INFORMATION
────────────────────
Gitea URL:        ${gitea_url}
External IP:      ${external_ip}
Internal IP:      ${instance_ip}
SSH Access:       ${ssh_command}
Admin User:       ${admin_username}
${password_line}

📦 STORAGE BUCKETS
────────────────────
Evidence Bucket:  ${evidence_bucket}
Backup Bucket:    ${backup_bucket}
Logs Bucket:      ${logs_bucket}

🔐 SERVICE ACCOUNTS
────────────────────
Gitea SA:         ${gitea_sa}
Evidence SA:      ${evidence_sa}
Backup SA:        ${backup_sa}

📋 NEXT STEPS
────────────────────
1. Configure DNS A record: ${DOMAIN} → ${external_ip}
2. Obtain SSL certificate (Let's Encrypt recommended)
3. Access Gitea and complete initial setup
4. Configure backup verification
5. Test monitoring alerts
6. Review security settings
7. Set up additional users

📊 EVIDENCE & LOGS
────────────────────
Deployment Log:   ${LOG_FILE}
Evidence File:    ${EVIDENCE_FILE}

🔧 USEFUL COMMANDS
────────────────────
View logs:        gcloud compute instances get-serial-port-output gitea-${ENVIRONMENT}-server --zone=${ZONE}
SSH to instance:  ${ssh_command}
Run backup:       ${SCRIPT_DIR}/gcp-backup.sh -p ${PROJECT_ID} -e ${ENVIRONMENT}
Check health:     curl -k https://${external_ip}/api/v1/version
EOF
    )

    print_color "${GREEN}" "${summary}"
}

# Generate deployment evidence JSON
generate_evidence() {
    local status="${1:-SUCCESS}"

    log INFO "Generating deployment evidence..."

    DEPLOYMENT_END=$(date -Iseconds)

    cd "${TERRAFORM_DIR}"

    # Collect infrastructure information
    local resources_json="{}"
    if [[ -f "terraform.tfstate" ]]; then
        resources_json=$(terraform show -json 2>/dev/null | jq -c '.values.root_module.resources' || echo "{}")
    fi

    # Generate evidence JSON
    cat > "${EVIDENCE_FILE}" <<EOF
{
  "deployment_id": "deploy_${TIMESTAMP}",
  "timestamp": "$(date -Iseconds)",
  "status": "${status}",
  "environment": "${ENVIRONMENT}",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "zone": "${ZONE}",
  "domain": "${DOMAIN}",
  "admin_email": "${ADMIN_EMAIL}",
  "deployment_start": "${DEPLOYMENT_START}",
  "deployment_end": "${DEPLOYMENT_END}",
  "duration_seconds": $(($(date +%s) - $(date -d "${DEPLOYMENT_START}" +%s))),
  "terraform_version": "$(terraform version -json | jq -r '.terraform_version')",
  "deployer": {
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "gcp_account": "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
  },
  "git_info": {
    "commit": "$(git -C '${PROJECT_ROOT}' rev-parse HEAD 2>/dev/null || echo 'N/A')",
    "branch": "$(git -C '${PROJECT_ROOT}' rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')",
    "status": "$(git -C '${PROJECT_ROOT}' status --porcelain | wc -l) uncommitted changes"
  },
  "infrastructure": {
    "terraform_initialized": ${TERRAFORM_INITIALIZED},
    "terraform_applied": ${TERRAFORM_APPLIED},
    "instance_ready": ${INSTANCE_READY},
    "gitea_accessible": ${GITEA_ACCESSIBLE}
  },
  "compliance": {
    "framework": "CMMC Level 2",
    "standards": ["NIST SP 800-171 Rev. 2", "NIST SP 800-218"],
    "controls": [
      "AC.L2-3.1.1",
      "AU.L2-3.3.1",
      "CM.L2-3.4.2",
      "SC.L2-3.13.11"
    ]
  },
  "evidence_hash": ""
}
EOF

    # Calculate hash of evidence file (excluding hash field)
    local evidence_hash
    evidence_hash=$(jq 'del(.evidence_hash)' "${EVIDENCE_FILE}" | sha256sum | cut -d' ' -f1)

    # Update evidence file with hash
    jq ".evidence_hash = \"${evidence_hash}\"" "${EVIDENCE_FILE}" > "${EVIDENCE_FILE}.tmp"
    mv "${EVIDENCE_FILE}.tmp" "${EVIDENCE_FILE}"

    log SUCCESS "Evidence file generated: ${EVIDENCE_FILE}"

    # Upload to GCS if bucket exists
    local evidence_bucket
    evidence_bucket=$(terraform output -raw evidence_bucket_name 2>/dev/null || echo "")

    if [[ -n "${evidence_bucket}" ]]; then
        log INFO "Uploading evidence to GCS..."
        if gsutil cp "${EVIDENCE_FILE}" "gs://${evidence_bucket}/deployments/"; then
            log SUCCESS "Evidence uploaded to gs://${evidence_bucket}/deployments/"
        else
            log WARNING "Failed to upload evidence to GCS"
        fi
    fi
}

# Cleanup on exit
cleanup() {
    local exit_code=$?

    if [[ ${exit_code} -ne 0 ]]; then
        log WARNING "Deployment script exited with code ${exit_code}"
        DEPLOYMENT_STATUS="FAILED"
    else
        DEPLOYMENT_STATUS="SUCCESS"
    fi

    # Generate evidence if not already done
    if [[ ! -f "${EVIDENCE_FILE}" ]]; then
        generate_evidence "${DEPLOYMENT_STATUS}"
    fi

    log INFO "Deployment script completed"
}

# Rollback on failure
rollback() {
    log ERROR "Initiating rollback..."

    cd "${TERRAFORM_DIR}"

    # Only rollback if we applied changes
    if [[ "${TERRAFORM_APPLIED}" == "true" ]]; then
        log WARNING "Rolling back Terraform changes..."

        if terraform destroy -auto-approve 2>&1 | tee -a "${LOG_FILE}"; then
            log SUCCESS "Rollback completed"
        else
            log ERROR "Rollback failed - manual intervention required"
        fi
    fi

    DEPLOYMENT_STATUS="ROLLED_BACK"
    generate_evidence "ROLLED_BACK"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    # Setup trap for cleanup
    trap cleanup EXIT
    trap 'rollback; exit 1' ERR

    # Parse arguments
    parse_args "$@"

    # Initialize
    init_directories

    # Start deployment
    print_color "${BLUE}" "
╔══════════════════════════════════════════════════════════════════╗
║               GCP GITEA DEPLOYMENT ORCHESTRATOR                  ║
║                    CMMC Level 2 Compliant                        ║
╚══════════════════════════════════════════════════════════════════╝
"

    log INFO "Starting deployment process..."

    # Validate parameters
    validate_params

    # Check prerequisites
    check_prerequisites

    # Check GCP permissions
    check_gcp_permissions

    # Enable APIs
    enable_apis

    # Generate terraform.tfvars
    generate_tfvars

    # Initialize Terraform
    terraform_init

    # Run Terraform plan
    terraform_plan

    # Confirm deployment
    confirm_deployment

    # Apply Terraform
    terraform_apply

    # Wait for instance
    wait_for_instance

    # Verify Gitea
    verify_gitea || true  # Don't fail if Gitea isn't accessible yet

    # Display results
    display_post_deployment

    # Generate evidence
    generate_evidence "SUCCESS"

    log SUCCESS "Deployment completed successfully!"

    return 0
}

# Run main function
main "$@"
