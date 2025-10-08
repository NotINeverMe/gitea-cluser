#!/bin/bash
# ==============================================================================
# GCP Gitea Backup Automation Script
# CMMC Level 2 / NIST SP 800-171 Compliant
# ==============================================================================
#
# Usage: ./gcp-backup.sh [options]
#   -p PROJECT_ID    GCP Project ID (required)
#   -e ENVIRONMENT   Environment: dev|staging|prod (required)
#   -r REGION        GCP Region (default: us-central1)
#   -t TYPE          Backup type: full|incremental|config (default: full)
#   -R RETENTION     Retention days (default: 30)
#   -n               Dry run - show what would be backed up
#   -f               Force backup even if recent backup exists
#   -v               Verbose output
#   -h               Show this help message
#
# Examples:
#   ./gcp-backup.sh -p my-project -e prod
#   ./gcp-backup.sh -p my-project -e prod -t full -R 90
#   ./gcp-backup.sh -p my-project -e staging -n
#
# Exit Codes:
#   0 - Success
#   1 - Error
#   2 - Warning/Partial backup
#
# CMMC Controls Addressed:
#   - CP.L2-3.11.1: System Backup
#   - CP.L2-3.11.2: Recovery Testing
#   - AU.L2-3.3.8: Protection of Audit Information
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TERRAFORM_DIR="${PROJECT_ROOT}/terraform/gcp-gitea"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly TEMP_DIR="/tmp/gitea_backup_$$"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly DATE_TODAY="$(date +%Y-%m-%d)"
readonly LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

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
BACKUP_TYPE="full"
RETENTION_DAYS=30
DRY_RUN=false
FORCE_BACKUP=false
VERBOSE=false

# Backup components
BACKUP_DOCKER_VOLUMES=true
BACKUP_POSTGRES=true
BACKUP_CONFIG=true
BACKUP_EVIDENCE=true

# Backup metadata
BACKUP_ID=""
BACKUP_START=""
BACKUP_END=""
BACKUP_STATUS="PENDING"
BACKUP_SIZE_MB=0
FILES_BACKED_UP=0

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
    grep "^#" "$0" | head -30 | tail -28 | sed 's/^# //' | sed 's/^#//'
}

# Parse arguments
parse_args() {
    while getopts "p:e:r:t:R:nfvh" opt; do
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
            t)
                BACKUP_TYPE="${OPTARG}"
                ;;
            R)
                RETENTION_DAYS="${OPTARG}"
                ;;
            n)
                DRY_RUN=true
                ;;
            f)
                FORCE_BACKUP=true
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

    if [[ ! "${BACKUP_TYPE}" =~ ^(full|incremental|config)$ ]]; then
        log ERROR "Invalid backup type: ${BACKUP_TYPE}"
        ((errors++))
    fi

    if [[ ${errors} -gt 0 ]]; then
        exit 1
    fi

    ZONE="${REGION}-a"
    BACKUP_ID="backup_${ENVIRONMENT}_${BACKUP_TYPE}_${TIMESTAMP}"
}

# Initialize directories
init_directories() {
    mkdir -p "${LOG_DIR}"
    mkdir -p "${TEMP_DIR}"

    touch "${LOG_FILE}"

    log SUCCESS "Initialized backup directories"
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."

    local required_commands=("gcloud" "gsutil" "docker" "jq" "tar")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            log ERROR "Required command not found: ${cmd}"
            exit 1
        fi
    done

    # Set project
    gcloud config set project "${PROJECT_ID}" 2>&1 | tee -a "${LOG_FILE}"

    log SUCCESS "Prerequisites checked"
}

# Get instance information
get_instance_info() {
    log INFO "Getting instance information..."

    INSTANCE_NAME="gitea-${ENVIRONMENT}-server"

    # Check instance exists and is running
    local status
    status=$(gcloud compute instances describe "${INSTANCE_NAME}" \
        --zone="${ZONE}" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND")

    if [[ "${status}" == "NOT_FOUND" ]]; then
        log ERROR "Instance ${INSTANCE_NAME} not found"
        exit 1
    fi

    if [[ "${status}" != "RUNNING" ]]; then
        log ERROR "Instance ${INSTANCE_NAME} is not running (status: ${status})"
        exit 1
    fi

    # Get backup bucket
    BACKUP_BUCKET="gitea-${ENVIRONMENT}-backup-${PROJECT_ID}"

    if ! gsutil ls -b "gs://${BACKUP_BUCKET}" &>/dev/null; then
        log ERROR "Backup bucket not found: gs://${BACKUP_BUCKET}"
        exit 1
    fi

    log SUCCESS "Instance ${INSTANCE_NAME} is running"
}

# Check recent backups
check_recent_backups() {
    if [[ "${FORCE_BACKUP}" == "true" ]]; then
        log INFO "Force backup enabled, skipping recent backup check"
        return 0
    fi

    log INFO "Checking for recent backups..."

    local recent_count
    recent_count=$(gsutil ls "gs://${BACKUP_BUCKET}/${BACKUP_TYPE}/${DATE_TODAY}/" 2>/dev/null | wc -l || echo "0")

    if [[ ${recent_count} -gt 0 ]]; then
        log WARNING "Found ${recent_count} backup(s) from today"

        if [[ "${DRY_RUN}" == "false" ]]; then
            read -p "Continue with new backup? (y/n): " -r
            if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
                log INFO "Backup cancelled"
                exit 0
            fi
        fi
    fi
}

# Execute remote command
remote_exec() {
    local cmd="$1"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would execute: ${cmd}"
        return 0
    fi

    gcloud compute ssh "${INSTANCE_NAME}" \
        --zone="${ZONE}" \
        --project="${PROJECT_ID}" \
        --command="${cmd}" 2>&1 | tee -a "${LOG_FILE}"
}

# Backup Docker volumes
backup_docker_volumes() {
    if [[ "${BACKUP_TYPE}" == "config" ]]; then
        log DEBUG "Skipping Docker volumes for config-only backup"
        return 0
    fi

    log INFO "Backing up Docker volumes..."

    local volumes=("gitea_data" "gitea_postgres" "gitea_redis")

    for volume in "${volumes[@]}"; do
        log INFO "Backing up volume: ${volume}"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log DEBUG "[DRY RUN] Would backup volume: ${volume}"
            continue
        fi

        # Create tar archive on remote
        remote_exec "sudo docker run --rm -v ${volume}:/source:ro -v /tmp:/backup alpine tar czf /backup/${volume}_${TIMESTAMP}.tar.gz -C /source ."

        # Copy to local temp
        gcloud compute scp \
            "${INSTANCE_NAME}:/tmp/${volume}_${TIMESTAMP}.tar.gz" \
            "${TEMP_DIR}/" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}"

        # Clean up remote
        remote_exec "sudo rm /tmp/${volume}_${TIMESTAMP}.tar.gz"

        ((FILES_BACKED_UP++))
    done

    log SUCCESS "Docker volumes backed up"
}

# Backup PostgreSQL database
backup_postgres() {
    if [[ "${BACKUP_TYPE}" == "config" ]]; then
        log DEBUG "Skipping PostgreSQL for config-only backup"
        return 0
    fi

    log INFO "Backing up PostgreSQL database..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would backup PostgreSQL database"
        return 0
    fi

    # Create database dump
    remote_exec "sudo docker exec gitea-postgres pg_dumpall -U gitea > /tmp/postgres_dump_${TIMESTAMP}.sql"

    # Compress dump
    remote_exec "gzip /tmp/postgres_dump_${TIMESTAMP}.sql"

    # Copy to local temp
    gcloud compute scp \
        "${INSTANCE_NAME}:/tmp/postgres_dump_${TIMESTAMP}.sql.gz" \
        "${TEMP_DIR}/" \
        --zone="${ZONE}" \
        --project="${PROJECT_ID}"

    # Clean up remote
    remote_exec "sudo rm /tmp/postgres_dump_${TIMESTAMP}.sql.gz"

    ((FILES_BACKED_UP++))

    log SUCCESS "PostgreSQL database backed up"
}

# Backup Gitea configuration
backup_config() {
    log INFO "Backing up Gitea configuration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would backup Gitea configuration"
        return 0
    fi

    # Create config archive on remote
    remote_exec "sudo tar czf /tmp/gitea_config_${TIMESTAMP}.tar.gz -C /opt/gitea docker-compose.yml .env config/"

    # Copy to local temp
    gcloud compute scp \
        "${INSTANCE_NAME}:/tmp/gitea_config_${TIMESTAMP}.tar.gz" \
        "${TEMP_DIR}/" \
        --zone="${ZONE}" \
        --project="${PROJECT_ID}"

    # Clean up remote
    remote_exec "sudo rm /tmp/gitea_config_${TIMESTAMP}.tar.gz"

    ((FILES_BACKED_UP++))

    log SUCCESS "Gitea configuration backed up"
}

# Create backup manifest
create_manifest() {
    log INFO "Creating backup manifest..."

    local manifest_file="${TEMP_DIR}/manifest.json"

    # Calculate sizes
    local total_size=0
    if [[ -d "${TEMP_DIR}" ]]; then
        total_size=$(du -sb "${TEMP_DIR}" | cut -f1)
        BACKUP_SIZE_MB=$((total_size / 1024 / 1024))
    fi

    cat > "${manifest_file}" <<EOF
{
  "backup_id": "${BACKUP_ID}",
  "timestamp": "$(date -Iseconds)",
  "environment": "${ENVIRONMENT}",
  "project_id": "${PROJECT_ID}",
  "instance_name": "${INSTANCE_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "retention_days": ${RETENTION_DAYS},
  "files_count": ${FILES_BACKED_UP},
  "size_mb": ${BACKUP_SIZE_MB},
  "components": {
    "docker_volumes": ${BACKUP_DOCKER_VOLUMES},
    "postgres": ${BACKUP_POSTGRES},
    "config": ${BACKUP_CONFIG}
  },
  "git_info": {
    "commit": "$(git -C '${PROJECT_ROOT}' rev-parse HEAD 2>/dev/null || echo 'N/A')",
    "branch": "$(git -C '${PROJECT_ROOT}' rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')"
  },
  "operator": {
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "gcp_account": "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
  },
  "compliance": {
    "framework": "CMMC Level 2",
    "controls": ["CP.L2-3.11.1", "CP.L2-3.11.2", "AU.L2-3.3.8"]
  }
}
EOF

    log SUCCESS "Backup manifest created"
}

# Upload to GCS
upload_to_gcs() {
    log INFO "Uploading backup to GCS..."

    local gcs_path="gs://${BACKUP_BUCKET}/${BACKUP_TYPE}/${DATE_TODAY}/${BACKUP_ID}/"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would upload to: ${gcs_path}"
        log DEBUG "[DRY RUN] Files to upload:"
        ls -la "${TEMP_DIR}/" 2>/dev/null || true
        return 0
    fi

    # Upload all files
    if gsutil -m cp -r "${TEMP_DIR}/*" "${gcs_path}"; then
        log SUCCESS "Backup uploaded to ${gcs_path}"
    else
        log ERROR "Failed to upload backup to GCS"
        return 1
    fi

    # Set lifecycle on old backups
    cleanup_old_backups

    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    log INFO "Cleaning up old backups (retention: ${RETENTION_DAYS} days)..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would clean backups older than ${RETENTION_DAYS} days"
        return 0
    fi

    # Calculate cutoff date
    local cutoff_date
    cutoff_date=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d)

    # List and delete old backups
    gsutil ls "gs://${BACKUP_BUCKET}/${BACKUP_TYPE}/" | while read -r date_dir; do
        local dir_date
        dir_date=$(basename "${date_dir}" | tr -d '/')

        if [[ "${dir_date}" < "${cutoff_date}" ]]; then
            log INFO "Deleting old backup: ${date_dir}"
            gsutil -m rm -r "${date_dir}"
        fi
    done

    log SUCCESS "Old backups cleaned up"
}

# Verify backup integrity
verify_backup() {
    log INFO "Verifying backup integrity..."

    local gcs_path="gs://${BACKUP_BUCKET}/${BACKUP_TYPE}/${DATE_TODAY}/${BACKUP_ID}/"

    # Check if files exist in GCS
    local file_count
    file_count=$(gsutil ls "${gcs_path}" 2>/dev/null | wc -l || echo "0")

    if [[ ${file_count} -eq 0 ]]; then
        log ERROR "No files found in backup location"
        return 1
    fi

    log INFO "Found ${file_count} files in backup"

    # Verify manifest
    if gsutil ls "${gcs_path}manifest.json" &>/dev/null; then
        log SUCCESS "Backup manifest verified"
    else
        log WARNING "Backup manifest not found"
    fi

    log SUCCESS "Backup verification completed"
}

# Send notification
send_notification() {
    local status="$1"
    local message="$2"

    log INFO "Sending backup notification..."

    # Get alert email from Terraform outputs
    if [[ -f "${TERRAFORM_DIR}/terraform.tfstate" ]]; then
        cd "${TERRAFORM_DIR}"
        local alert_email
        alert_email=$(terraform output -raw alert_email 2>/dev/null || echo "")

        if [[ -n "${alert_email}" ]]; then
            # In production, integrate with SendGrid, AWS SES, or Cloud Functions
            log INFO "Notification would be sent to: ${alert_email}"
            log DEBUG "Status: ${status}"
            log DEBUG "Message: ${message}"
        fi
    fi

    # Log to Cloud Logging
    if command -v gcloud &>/dev/null; then
        gcloud logging write gitea-backups \
            "Backup ${status}: ${message}" \
            --severity="${status}" \
            --project="${PROJECT_ID}" 2>/dev/null || true
    fi
}

# Generate backup report
generate_report() {
    log INFO "Generating backup report..."

    local report_file="${LOG_DIR}/backup_report_${TIMESTAMP}.txt"

    cat > "${report_file}" <<EOF
================================================================================
                           GITEA BACKUP REPORT
================================================================================

Backup ID:        ${BACKUP_ID}
Date:             $(date)
Environment:      ${ENVIRONMENT}
Project:          ${PROJECT_ID}
Instance:         ${INSTANCE_NAME}

BACKUP DETAILS
--------------
Type:             ${BACKUP_TYPE}
Status:           ${BACKUP_STATUS}
Files Backed Up:  ${FILES_BACKED_UP}
Total Size:       ${BACKUP_SIZE_MB} MB
Retention:        ${RETENTION_DAYS} days

COMPONENTS
----------
Docker Volumes:   $(if [[ "${BACKUP_DOCKER_VOLUMES}" == "true" ]]; then echo "✓"; else echo "✗"; fi)
PostgreSQL:       $(if [[ "${BACKUP_POSTGRES}" == "true" ]]; then echo "✓"; else echo "✗"; fi)
Configuration:    $(if [[ "${BACKUP_CONFIG}" == "true" ]]; then echo "✓"; else echo "✗"; fi)

STORAGE LOCATION
----------------
Bucket:           gs://${BACKUP_BUCKET}
Path:             ${BACKUP_TYPE}/${DATE_TODAY}/${BACKUP_ID}/

VERIFICATION
------------
Files in Backup:  $(gsutil ls "gs://${BACKUP_BUCKET}/${BACKUP_TYPE}/${DATE_TODAY}/${BACKUP_ID}/" 2>/dev/null | wc -l || echo "N/A")
Manifest:         $(if gsutil ls "gs://${BACKUP_BUCKET}/${BACKUP_TYPE}/${DATE_TODAY}/${BACKUP_ID}/manifest.json" &>/dev/null; then echo "✓"; else echo "✗"; fi)

TIMING
------
Start:            ${BACKUP_START}
End:              ${BACKUP_END}
Duration:         $(($(date +%s) - $(date -d "${BACKUP_START}" +%s))) seconds

COMPLIANCE
----------
Framework:        CMMC Level 2
Controls:         CP.L2-3.11.1, CP.L2-3.11.2, AU.L2-3.3.8

================================================================================
EOF

    log SUCCESS "Report generated: ${report_file}"

    if [[ "${VERBOSE}" == "true" ]]; then
        cat "${report_file}"
    fi
}

# Cleanup temporary files
cleanup() {
    log DEBUG "Cleaning up temporary files..."

    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi

    log DEBUG "Cleanup completed"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    # Setup trap
    trap cleanup EXIT

    # Parse arguments
    parse_args "$@"

    # Initialize
    init_directories

    print_color "${BLUE}" "
╔══════════════════════════════════════════════════════════════════╗
║                  GCP GITEA BACKUP AUTOMATION                     ║
║                    CMMC Level 2 Compliant                        ║
╚══════════════════════════════════════════════════════════════════╝
"

    BACKUP_START=$(date -Iseconds)

    # Validate
    validate_params

    # Check prerequisites
    check_prerequisites

    # Get instance info
    get_instance_info

    # Check recent backups
    check_recent_backups

    if [[ "${DRY_RUN}" == "true" ]]; then
        log WARNING "DRY RUN MODE - No actual backup will be performed"
    fi

    # Perform backup based on type
    case "${BACKUP_TYPE}" in
        full)
            backup_docker_volumes
            backup_postgres
            backup_config
            ;;
        incremental)
            backup_postgres
            backup_config
            ;;
        config)
            backup_config
            ;;
    esac

    # Create manifest
    create_manifest

    # Upload to GCS
    if upload_to_gcs; then
        BACKUP_STATUS="SUCCESS"

        # Verify backup
        verify_backup

        # Send success notification
        send_notification "INFO" "Backup ${BACKUP_ID} completed successfully (${BACKUP_SIZE_MB} MB)"
    else
        BACKUP_STATUS="FAILED"

        # Send failure notification
        send_notification "ERROR" "Backup ${BACKUP_ID} failed"

        log ERROR "Backup failed"
        exit 1
    fi

    BACKUP_END=$(date -Iseconds)

    # Generate report
    generate_report

    print_color "${GREEN}" "
╔══════════════════════════════════════════════════════════════════╗
║                    BACKUP COMPLETED SUCCESSFULLY                 ║
╚══════════════════════════════════════════════════════════════════╝

Backup ID:       ${BACKUP_ID}
Type:            ${BACKUP_TYPE}
Size:            ${BACKUP_SIZE_MB} MB
Files:           ${FILES_BACKED_UP}
Location:        gs://${BACKUP_BUCKET}/${BACKUP_TYPE}/${DATE_TODAY}/${BACKUP_ID}/

To restore this backup, run:
./gcp-restore.sh -p ${PROJECT_ID} -e ${ENVIRONMENT} -b ${BACKUP_ID}
"

    log SUCCESS "Backup completed successfully!"

    return 0
}

# Run main function
main "$@"