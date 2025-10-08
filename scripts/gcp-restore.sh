#!/bin/bash
# ==============================================================================
# GCP Gitea Disaster Recovery / Restore Script
# CMMC Level 2 / NIST SP 800-171 Compliant
# ==============================================================================
#
# Usage: ./gcp-restore.sh [options]
#   -p PROJECT_ID    GCP Project ID (required)
#   -e ENVIRONMENT   Environment: dev|staging|prod (required)
#   -b BACKUP_ID     Specific backup ID to restore (optional)
#   -d DATE          Date of backup (YYYY-MM-DD) (optional)
#   -r REGION        GCP Region (default: us-central1)
#   -l               List available backups only
#   -n               Dry run - show what would be restored
#   -f               Force restore without confirmation
#   -v               Verbose output
#   -h               Show this help message
#
# Examples:
#   ./gcp-restore.sh -p my-project -e prod -l                    # List backups
#   ./gcp-restore.sh -p my-project -e prod -b backup_id          # Restore specific
#   ./gcp-restore.sh -p my-project -e prod -d 2024-01-15        # Restore from date
#   ./gcp-restore.sh -p my-project -e staging -n                 # Dry run
#
# Exit Codes:
#   0 - Success
#   1 - Error
#   2 - Warning/Partial restore
#
# CMMC Controls Addressed:
#   - CP.L2-3.11.2: Recovery Testing
#   - CP.L2-3.11.3: Backup Protection
#   - SI.L2-3.14.3: Security Alerts
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly TEMP_DIR="/tmp/gitea_restore_$$"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${LOG_DIR}/restore_${TIMESTAMP}.log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Default values
ENVIRONMENT=""
PROJECT_ID=""
REGION="us-central1"
ZONE=""
BACKUP_ID=""
BACKUP_DATE=""
LIST_ONLY=false
DRY_RUN=false
FORCE_RESTORE=false
VERBOSE=false

# Restore state
RESTORE_ID=""
RESTORE_START=""
RESTORE_END=""
RESTORE_STATUS="PENDING"
COMPONENTS_RESTORED=0

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
    grep "^#" "$0" | head -34 | tail -32 | sed 's/^# //' | sed 's/^#//'
}

# Parse arguments
parse_args() {
    while getopts "p:e:b:d:r:lnfvh" opt; do
        case ${opt} in
            p)
                PROJECT_ID="${OPTARG}"
                ;;
            e)
                ENVIRONMENT="${OPTARG}"
                ;;
            b)
                BACKUP_ID="${OPTARG}"
                ;;
            d)
                BACKUP_DATE="${OPTARG}"
                ;;
            r)
                REGION="${OPTARG}"
                ;;
            l)
                LIST_ONLY=true
                ;;
            n)
                DRY_RUN=true
                ;;
            f)
                FORCE_RESTORE=true
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
    INSTANCE_NAME="gitea-${ENVIRONMENT}-server"
    BACKUP_BUCKET="gitea-${ENVIRONMENT}-backup-${PROJECT_ID}"
    RESTORE_ID="restore_${ENVIRONMENT}_${TIMESTAMP}"
}

# Initialize
init_directories() {
    mkdir -p "${LOG_DIR}"
    mkdir -p "${TEMP_DIR}"

    touch "${LOG_FILE}"

    log DEBUG "Initialized directories"
}

# List available backups
list_backups() {
    log INFO "Listing available backups for ${ENVIRONMENT}..."

    print_color "${CYAN}" "
╔══════════════════════════════════════════════════════════════════╗
║                      AVAILABLE BACKUPS                           ║
╚══════════════════════════════════════════════════════════════════╝
"

    # List backup types
    local backup_types=("full" "incremental" "config")

    for type in "${backup_types[@]}"; do
        print_color "${YELLOW}" "\n${type^^} BACKUPS:"
        print_color "${CYAN}" "────────────────────"

        # List dates for this type
        gsutil ls "gs://${BACKUP_BUCKET}/${type}/" 2>/dev/null | while read -r date_dir; do
            local date_path
            date_path=$(basename "${date_dir}" | tr -d '/')

            # List backups for this date
            gsutil ls "${date_dir}" 2>/dev/null | while read -r backup_dir; do
                local backup_name
                backup_name=$(basename "${backup_dir}" | tr -d '/')

                # Get manifest info if available
                local size="N/A"
                local files="N/A"

                if gsutil cat "${backup_dir}manifest.json" 2>/dev/null | jq -e . >/dev/null 2>&1; then
                    local manifest
                    manifest=$(gsutil cat "${backup_dir}manifest.json" 2>/dev/null)
                    size=$(echo "${manifest}" | jq -r '.size_mb // "N/A"')
                    files=$(echo "${manifest}" | jq -r '.files_count // "N/A"')
                fi

                printf "  %-50s │ %s │ %5s MB │ %3s files\n" \
                    "${backup_name}" "${date_path}" "${size}" "${files}"
            done
        done
    done

    print_color "${CYAN}" "
────────────────────────────────────────────────────────────────────

To restore a specific backup, use:
  ./gcp-restore.sh -p ${PROJECT_ID} -e ${ENVIRONMENT} -b BACKUP_ID

To restore from a specific date, use:
  ./gcp-restore.sh -p ${PROJECT_ID} -e ${ENVIRONMENT} -d YYYY-MM-DD
"
}

# Select backup to restore
select_backup() {
    log INFO "Selecting backup to restore..."

    local backup_path=""

    if [[ -n "${BACKUP_ID}" ]]; then
        # Find backup by ID
        log INFO "Searching for backup ID: ${BACKUP_ID}"

        for type in "full" "incremental" "config"; do
            local result
            result=$(gsutil ls -r "gs://${BACKUP_BUCKET}/${type}/**/${BACKUP_ID}/" 2>/dev/null | head -1 || echo "")

            if [[ -n "${result}" ]]; then
                backup_path="${result}"
                break
            fi
        done

        if [[ -z "${backup_path}" ]]; then
            log ERROR "Backup not found: ${BACKUP_ID}"
            exit 1
        fi

    elif [[ -n "${BACKUP_DATE}" ]]; then
        # Find latest full backup from date
        log INFO "Searching for backups from date: ${BACKUP_DATE}"

        backup_path=$(gsutil ls "gs://${BACKUP_BUCKET}/full/${BACKUP_DATE}/" 2>/dev/null | tail -1 || echo "")

        if [[ -z "${backup_path}" ]]; then
            log ERROR "No full backup found for date: ${BACKUP_DATE}"
            exit 1
        fi

    else
        # Find latest full backup
        log INFO "Selecting latest full backup..."

        backup_path=$(gsutil ls -r "gs://${BACKUP_BUCKET}/full/" 2>/dev/null | grep "/$" | tail -1 || echo "")

        if [[ -z "${backup_path}" ]]; then
            log ERROR "No full backups found"
            exit 1
        fi
    fi

    SELECTED_BACKUP="${backup_path}"
    log SUCCESS "Selected backup: ${SELECTED_BACKUP}"

    # Download and display manifest
    if gsutil cat "${SELECTED_BACKUP}manifest.json" 2>/dev/null | jq -e . >/dev/null 2>&1; then
        local manifest
        manifest=$(gsutil cat "${SELECTED_BACKUP}manifest.json" 2>/dev/null)

        print_color "${CYAN}" "
Backup Details:
───────────────
Backup ID:     $(echo "${manifest}" | jq -r '.backup_id')
Type:          $(echo "${manifest}" | jq -r '.backup_type')
Date:          $(echo "${manifest}" | jq -r '.timestamp')
Size:          $(echo "${manifest}" | jq -r '.size_mb') MB
Files:         $(echo "${manifest}" | jq -r '.files_count')
Environment:   $(echo "${manifest}" | jq -r '.environment')
"
    fi
}

# Confirm restore
confirm_restore() {
    if [[ "${FORCE_RESTORE}" == "true" ]]; then
        log INFO "Force restore enabled, skipping confirmation"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log INFO "Dry run mode, skipping confirmation"
        return 0
    fi

    print_color "${YELLOW}" "
╔══════════════════════════════════════════════════════════════════╗
║                         ⚠ WARNING ⚠                              ║
╠══════════════════════════════════════════════════════════════════╣
║ This will OVERWRITE the current Gitea installation!              ║
║                                                                   ║
║ Instance:     ${INSTANCE_NAME}
║ Environment:  ${ENVIRONMENT}
║ Backup:       $(basename "${SELECTED_BACKUP}")
╚══════════════════════════════════════════════════════════════════╝
"

    read -p "Are you sure you want to restore? Type 'yes' to confirm: " -r

    if [[ "${REPLY}" != "yes" ]]; then
        log WARNING "Restore cancelled by user"
        exit 0
    fi
}

# Create pre-restore backup
create_pre_restore_backup() {
    log INFO "Creating pre-restore backup for safety..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would create pre-restore backup"
        return 0
    fi

    # Run backup script
    if [[ -x "${SCRIPT_DIR}/gcp-backup.sh" ]]; then
        "${SCRIPT_DIR}/gcp-backup.sh" \
            -p "${PROJECT_ID}" \
            -e "${ENVIRONMENT}" \
            -r "${REGION}" \
            -t full \
            -f || log WARNING "Pre-restore backup failed (continuing anyway)"
    else
        log WARNING "Backup script not found, skipping pre-restore backup"
    fi
}

# Download backup files
download_backup() {
    log INFO "Downloading backup files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would download from: ${SELECTED_BACKUP}"
        return 0
    fi

    # Download all files from backup
    if gsutil -m cp -r "${SELECTED_BACKUP}*" "${TEMP_DIR}/"; then
        log SUCCESS "Backup files downloaded"

        # List downloaded files
        log DEBUG "Downloaded files:"
        ls -la "${TEMP_DIR}/" | while read -r line; do
            log DEBUG "  ${line}"
        done
    else
        log ERROR "Failed to download backup files"
        exit 1
    fi
}

# Stop services
stop_services() {
    log INFO "Stopping Gitea services..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would stop services"
        return 0
    fi

    # Stop Docker containers
    gcloud compute ssh "${INSTANCE_NAME}" \
        --zone="${ZONE}" \
        --project="${PROJECT_ID}" \
        --command="cd /opt/gitea && sudo docker-compose down" 2>&1 | tee -a "${LOG_FILE}"

    log SUCCESS "Services stopped"
}

# Restore Docker volumes
restore_docker_volumes() {
    log INFO "Restoring Docker volumes..."

    local volumes=("gitea_data" "gitea_postgres" "gitea_redis")

    for volume in "${volumes[@]}"; do
        local archive="${TEMP_DIR}/${volume}_*.tar.gz"

        if ls ${archive} 1> /dev/null 2>&1; then
            log INFO "Restoring volume: ${volume}"

            if [[ "${DRY_RUN}" == "true" ]]; then
                log DEBUG "[DRY RUN] Would restore volume: ${volume}"
                continue
            fi

            # Upload archive to instance
            local archive_file
            archive_file=$(ls ${archive} | head -1)
            local remote_file="/tmp/$(basename "${archive_file}")"

            gcloud compute scp \
                "${archive_file}" \
                "${INSTANCE_NAME}:${remote_file}" \
                --zone="${ZONE}" \
                --project="${PROJECT_ID}"

            # Clear and restore volume
            gcloud compute ssh "${INSTANCE_NAME}" \
                --zone="${ZONE}" \
                --project="${PROJECT_ID}" \
                --command="
                    sudo docker volume rm ${volume} 2>/dev/null || true
                    sudo docker volume create ${volume}
                    sudo docker run --rm -v ${volume}:/target -v /tmp:/backup alpine tar xzf /backup/$(basename "${remote_file}") -C /target
                    sudo rm ${remote_file}
                " 2>&1 | tee -a "${LOG_FILE}"

            ((COMPONENTS_RESTORED++))
            log SUCCESS "Volume restored: ${volume}"
        else
            log WARNING "Volume archive not found: ${volume}"
        fi
    done
}

# Restore PostgreSQL database
restore_postgres() {
    log INFO "Restoring PostgreSQL database..."

    local dump_file="${TEMP_DIR}/postgres_dump_*.sql.gz"

    if ls ${dump_file} 1> /dev/null 2>&1; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log DEBUG "[DRY RUN] Would restore PostgreSQL database"
            return 0
        fi

        # Upload dump to instance
        local dump_path
        dump_path=$(ls ${dump_file} | head -1)
        local remote_dump="/tmp/$(basename "${dump_path}")"

        gcloud compute scp \
            "${dump_path}" \
            "${INSTANCE_NAME}:${remote_dump}" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}"

        # Start only PostgreSQL container
        gcloud compute ssh "${INSTANCE_NAME}" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}" \
            --command="
                cd /opt/gitea
                sudo docker-compose up -d postgres
                sleep 10
                gunzip -c ${remote_dump} | sudo docker exec -i gitea-postgres psql -U gitea
                sudo rm ${remote_dump}
            " 2>&1 | tee -a "${LOG_FILE}"

        ((COMPONENTS_RESTORED++))
        log SUCCESS "PostgreSQL database restored"
    else
        log WARNING "PostgreSQL dump not found in backup"
    fi
}

# Restore configuration
restore_config() {
    log INFO "Restoring Gitea configuration..."

    local config_archive="${TEMP_DIR}/gitea_config_*.tar.gz"

    if ls ${config_archive} 1> /dev/null 2>&1; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log DEBUG "[DRY RUN] Would restore configuration"
            return 0
        fi

        # Upload and extract config
        local archive_path
        archive_path=$(ls ${config_archive} | head -1)
        local remote_archive="/tmp/$(basename "${archive_path}")"

        gcloud compute scp \
            "${archive_path}" \
            "${INSTANCE_NAME}:${remote_archive}" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}"

        gcloud compute ssh "${INSTANCE_NAME}" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}" \
            --command="
                sudo tar xzf ${remote_archive} -C /opt/gitea
                sudo chown -R 1000:1000 /opt/gitea
                sudo rm ${remote_archive}
            " 2>&1 | tee -a "${LOG_FILE}"

        ((COMPONENTS_RESTORED++))
        log SUCCESS "Configuration restored"
    else
        log WARNING "Configuration archive not found in backup"
    fi
}

# Start services
start_services() {
    log INFO "Starting Gitea services..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would start services"
        return 0
    fi

    gcloud compute ssh "${INSTANCE_NAME}" \
        --zone="${ZONE}" \
        --project="${PROJECT_ID}" \
        --command="cd /opt/gitea && sudo docker-compose up -d" 2>&1 | tee -a "${LOG_FILE}"

    # Wait for services to start
    sleep 30

    log SUCCESS "Services started"
}

# Verify restoration
verify_restoration() {
    log INFO "Verifying restoration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log DEBUG "[DRY RUN] Would verify restoration"
        return 0
    fi

    local external_ip
    external_ip=$(gcloud compute instances describe "${INSTANCE_NAME}" \
        --zone="${ZONE}" \
        --project="${PROJECT_ID}" \
        --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

    # Check Gitea health
    local max_attempts=10
    local attempt=0
    local healthy=false

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        ((attempt++))
        log DEBUG "Health check attempt ${attempt}/${max_attempts}..."

        if curl -s "http://${external_ip}:3000/api/v1/version" 2>/dev/null | grep -q "version"; then
            healthy=true
            break
        fi

        sleep 10
    done

    if [[ "${healthy}" == "true" ]]; then
        log SUCCESS "Gitea is healthy and responding"

        # Get version info
        local version_info
        version_info=$(curl -s "http://${external_ip}:3000/api/v1/version" 2>/dev/null || echo "{}")

        log INFO "Gitea version: $(echo "${version_info}" | jq -r '.version // "unknown"')"
    else
        log WARNING "Gitea health check failed - manual verification required"
        return 2
    fi

    # Check database connectivity
    gcloud compute ssh "${INSTANCE_NAME}" \
        --zone="${ZONE}" \
        --project="${PROJECT_ID}" \
        --command="sudo docker exec gitea-postgres pg_isready -U gitea" 2>&1 | tee -a "${LOG_FILE}"

    log SUCCESS "Restoration verification completed"
}

# Generate restoration evidence
generate_evidence() {
    log INFO "Generating restoration evidence..."

    local evidence_file="${LOG_DIR}/restore_evidence_${TIMESTAMP}.json"

    cat > "${evidence_file}" <<EOF
{
  "restore_id": "${RESTORE_ID}",
  "timestamp": "$(date -Iseconds)",
  "status": "${RESTORE_STATUS}",
  "environment": "${ENVIRONMENT}",
  "project_id": "${PROJECT_ID}",
  "instance_name": "${INSTANCE_NAME}",
  "backup_restored": "$(basename "${SELECTED_BACKUP}")",
  "components_restored": ${COMPONENTS_RESTORED},
  "restore_start": "${RESTORE_START}",
  "restore_end": "${RESTORE_END}",
  "duration_seconds": $(($(date +%s) - $(date -d "${RESTORE_START}" +%s))),
  "operator": {
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "gcp_account": "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
  },
  "compliance": {
    "framework": "CMMC Level 2",
    "controls": ["CP.L2-3.11.2", "CP.L2-3.11.3", "SI.L2-3.14.3"]
  }
}
EOF

    log SUCCESS "Evidence file generated: ${evidence_file}"

    # Upload to evidence bucket if available
    local evidence_bucket="gitea-${ENVIRONMENT}-evidence-${PROJECT_ID}"

    if gsutil ls -b "gs://${evidence_bucket}" &>/dev/null; then
        gsutil cp "${evidence_file}" "gs://${evidence_bucket}/restorations/"
        log SUCCESS "Evidence uploaded to GCS"
    fi
}

# Cleanup
cleanup() {
    log DEBUG "Cleaning up..."

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
║               GCP GITEA DISASTER RECOVERY                        ║
║                    CMMC Level 2 Compliant                        ║
╚══════════════════════════════════════════════════════════════════╝
"

    RESTORE_START=$(date -Iseconds)

    # Validate
    validate_params

    # Set project
    gcloud config set project "${PROJECT_ID}" 2>&1 | tee -a "${LOG_FILE}"

    # List backups if requested
    if [[ "${LIST_ONLY}" == "true" ]]; then
        list_backups
        exit 0
    fi

    # Select backup
    select_backup

    # Confirm restore
    confirm_restore

    if [[ "${DRY_RUN}" == "true" ]]; then
        log WARNING "DRY RUN MODE - No actual restore will be performed"
    fi

    # Create pre-restore backup
    create_pre_restore_backup

    # Download backup
    download_backup

    # Stop services
    stop_services

    # Restore components
    restore_docker_volumes
    restore_postgres
    restore_config

    # Start services
    start_services

    # Verify restoration
    if verify_restoration; then
        RESTORE_STATUS="SUCCESS"
    else
        RESTORE_STATUS="PARTIAL"
    fi

    RESTORE_END=$(date -Iseconds)

    # Generate evidence
    generate_evidence

    print_color "${GREEN}" "
╔══════════════════════════════════════════════════════════════════╗
║                 RESTORATION COMPLETED SUCCESSFULLY               ║
╚══════════════════════════════════════════════════════════════════╝

Restore ID:        ${RESTORE_ID}
Status:            ${RESTORE_STATUS}
Components:        ${COMPONENTS_RESTORED} restored
Duration:          $(($(date +%s) - $(date -d "${RESTORE_START}" +%s))) seconds

Instance:          ${INSTANCE_NAME}
Environment:       ${ENVIRONMENT}

Next Steps:
1. Verify application functionality
2. Check data integrity
3. Test user authentication
4. Review logs for any issues
5. Update DNS if needed

Access Gitea:
gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --tunnel-through-iap
"

    log SUCCESS "Restoration completed!"

    return 0
}

# Run main function
main "$@"