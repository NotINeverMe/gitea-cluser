#!/bin/bash

# Grafana Backup Script
# CMMC 2.0: CP.L2-3.4.7 - Backup
# NIST SP 800-171: 3.4.7 - Backup
# NIST SP 800-53: CP-9 - Information System Backup

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backup/grafana}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_API_KEY="${GRAFANA_API_KEY}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-grafana-postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-90}"
EVIDENCE_DIR="../compliance/evidence/backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="grafana-backup-${TIMESTAMP}"

# Logging
LOG_FILE="/var/log/grafana-backup-${TIMESTAMP}.log"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    generate_evidence "failed" "$1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Generate compliance evidence
generate_evidence() {
    local status=$1
    local details=${2:-""}
    local evidence_file="$EVIDENCE_DIR/grafana-backup-${TIMESTAMP}.json"

    mkdir -p "$EVIDENCE_DIR"

    cat > "$evidence_file" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "backup_name": "$BACKUP_NAME",
  "status": "$status",
  "details": "$details",
  "compliance": {
    "cmmc": ["CP.L2-3.4.7"],
    "nist_171": ["3.4.7"],
    "nist_53": ["CP-9"]
  },
  "retention_days": $RETENTION_DAYS,
  "backup_location": "$BACKUP_DIR/$BACKUP_NAME",
  "hash": "$(sha256sum $LOG_FILE 2>/dev/null | cut -d' ' -f1 || echo 'pending')"
}
EOF

    log "Evidence generated: $evidence_file"
}

# Create backup directory
create_backup_dir() {
    log "Creating backup directory..."
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME"/{dashboards,datasources,alerts,database}
    chmod 700 "$BACKUP_DIR/$BACKUP_NAME"
}

# Backup Grafana dashboards
backup_dashboards() {
    log "Backing up dashboards..."

    if [ -z "$GRAFANA_API_KEY" ]; then
        warning "GRAFANA_API_KEY not set, trying with admin credentials"
        AUTH_HEADER="Authorization: Basic $(echo -n 'admin:ChangeMe123!' | base64)"
    else
        AUTH_HEADER="Authorization: Bearer $GRAFANA_API_KEY"
    fi

    # Get all dashboards
    dashboards=$(curl -s -H "$AUTH_HEADER" \
        "$GRAFANA_URL/api/search?type=dash-db" | \
        jq -r '.[] | @base64')

    if [ -z "$dashboards" ]; then
        warning "No dashboards found to backup"
        return
    fi

    local count=0
    for dashboard in $dashboards; do
        dashboard_data=$(echo "$dashboard" | base64 -d)
        uid=$(echo "$dashboard_data" | jq -r '.uid')
        title=$(echo "$dashboard_data" | jq -r '.title' | sed 's/[^a-zA-Z0-9-]/_/g')

        log "Backing up dashboard: $title (UID: $uid)"

        # Get dashboard JSON
        curl -s -H "$AUTH_HEADER" \
            "$GRAFANA_URL/api/dashboards/uid/$uid" | \
            jq '.' > "$BACKUP_DIR/$BACKUP_NAME/dashboards/${title}_${uid}.json"

        count=$((count + 1))
    done

    log "Backed up $count dashboards"
}

# Backup data sources
backup_datasources() {
    log "Backing up data sources..."

    if [ -z "$GRAFANA_API_KEY" ]; then
        AUTH_HEADER="Authorization: Basic $(echo -n 'admin:ChangeMe123!' | base64)"
    else
        AUTH_HEADER="Authorization: Bearer $GRAFANA_API_KEY"
    fi

    curl -s -H "$AUTH_HEADER" \
        "$GRAFANA_URL/api/datasources" | \
        jq '.' > "$BACKUP_DIR/$BACKUP_NAME/datasources/datasources.json"

    log "Data sources backed up"
}

# Backup alert rules
backup_alerts() {
    log "Backing up alert rules..."

    if [ -z "$GRAFANA_API_KEY" ]; then
        AUTH_HEADER="Authorization: Basic $(echo -n 'admin:ChangeMe123!' | base64)"
    else
        AUTH_HEADER="Authorization: Bearer $GRAFANA_API_KEY"
    fi

    # Backup alert rules
    curl -s -H "$AUTH_HEADER" \
        "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" | \
        jq '.' > "$BACKUP_DIR/$BACKUP_NAME/alerts/alert_rules.json"

    # Backup notification channels
    curl -s -H "$AUTH_HEADER" \
        "$GRAFANA_URL/api/alert-notifications" | \
        jq '.' > "$BACKUP_DIR/$BACKUP_NAME/alerts/notification_channels.json"

    log "Alert rules backed up"
}

# Backup PostgreSQL database
backup_database() {
    log "Backing up PostgreSQL database..."

    # Check if container is running
    if ! docker ps --format "{{.Names}}" | grep -q "^${POSTGRES_CONTAINER}$"; then
        warning "PostgreSQL container not running, skipping database backup"
        return
    fi

    # Perform database dump
    docker exec "$POSTGRES_CONTAINER" \
        pg_dump -U grafana -d grafana \
        > "$BACKUP_DIR/$BACKUP_NAME/database/grafana.sql"

    # Compress the dump
    gzip "$BACKUP_DIR/$BACKUP_NAME/database/grafana.sql"

    log "Database backed up and compressed"
}

# Backup Grafana configuration
backup_configuration() {
    log "Backing up Grafana configuration..."

    # Copy provisioning configurations
    if [ -d "monitoring/grafana/provisioning" ]; then
        cp -r monitoring/grafana/provisioning "$BACKUP_DIR/$BACKUP_NAME/"
        log "Provisioning configurations backed up"
    fi

    # Copy custom configurations
    if [ -f "monitoring/grafana/grafana.ini" ]; then
        cp monitoring/grafana/grafana.ini "$BACKUP_DIR/$BACKUP_NAME/"
        log "Custom configuration backed up"
    fi
}

# Create backup archive
create_archive() {
    log "Creating backup archive..."

    cd "$BACKUP_DIR"

    # Create tarball with compression
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME/"

    # Generate checksum
    sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.tar.gz.sha256"

    # Encrypt backup (optional)
    if [ -n "${BACKUP_ENCRYPTION_KEY:-}" ]; then
        log "Encrypting backup..."
        openssl enc -aes-256-cbc -salt -in "${BACKUP_NAME}.tar.gz" \
            -out "${BACKUP_NAME}.tar.gz.enc" -pass pass:"$BACKUP_ENCRYPTION_KEY"

        # Remove unencrypted archive
        rm "${BACKUP_NAME}.tar.gz"
        sha256sum "${BACKUP_NAME}.tar.gz.enc" > "${BACKUP_NAME}.tar.gz.enc.sha256"
    fi

    # Remove temporary directory
    rm -rf "$BACKUP_NAME/"

    log "Backup archive created"
}

# Upload to remote storage (optional)
upload_backup() {
    log "Uploading backup to remote storage..."

    # GCS upload example
    if [ -n "${GCS_BUCKET:-}" ]; then
        gsutil cp "$BACKUP_DIR/${BACKUP_NAME}.tar.gz*" "gs://$GCS_BUCKET/grafana-backups/"
        log "Backup uploaded to GCS bucket: $GCS_BUCKET"
    fi

    # AWS S3 upload example
    if [ -n "${S3_BUCKET:-}" ]; then
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.tar.gz*" "s3://$S3_BUCKET/grafana-backups/"
        log "Backup uploaded to S3 bucket: $S3_BUCKET"
    fi
}

# Clean old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."

    # Find and remove backups older than retention period
    find "$BACKUP_DIR" -name "grafana-backup-*.tar.gz*" -type f -mtime +$RETENTION_DAYS -exec rm {} \;

    log "Old backups cleaned up (retention: $RETENTION_DAYS days)"
}

# Verify backup
verify_backup() {
    log "Verifying backup..."

    local backup_file="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"

    if [ -n "${BACKUP_ENCRYPTION_KEY:-}" ]; then
        backup_file="${backup_file}.enc"
    fi

    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
    fi

    # Verify checksum
    if [ -f "${backup_file}.sha256" ]; then
        if sha256sum -c "${backup_file}.sha256" > /dev/null 2>&1; then
            log "Backup checksum verified"
        else
            error "Backup checksum verification failed"
        fi
    fi

    # Check file size
    local size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file")
    if [ "$size" -lt 1000 ]; then
        error "Backup file too small: $size bytes"
    fi

    log "Backup verified successfully (size: $size bytes)"
}

# Send notification
send_notification() {
    local status=$1

    # Send to monitoring system
    if [ -n "${MONITORING_WEBHOOK:-}" ]; then
        curl -X POST "$MONITORING_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"text\": \"Grafana Backup $status\",
                \"backup\": \"$BACKUP_NAME\",
                \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
            }" || true
    fi

    # Update Prometheus metric
    if [ -n "${PROMETHEUS_PUSHGATEWAY:-}" ]; then
        echo "backup_last_successful_timestamp $(date +%s)" | \
            curl --data-binary @- "$PROMETHEUS_PUSHGATEWAY/metrics/job/grafana-backup"
    fi
}

# Main backup process
main() {
    log "Starting Grafana backup..."

    # Change to project root
    cd "$(dirname "$0")/.."

    # Create backup directory
    create_backup_dir

    # Perform backups
    backup_dashboards
    backup_datasources
    backup_alerts
    backup_database
    backup_configuration

    # Create archive
    create_archive

    # Upload to remote storage
    upload_backup

    # Clean old backups
    cleanup_old_backups

    # Verify backup
    verify_backup

    # Generate evidence
    generate_evidence "success" "Backup completed successfully"

    # Send notification
    send_notification "SUCCESS"

    log "Grafana backup completed successfully"
    log "Backup location: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
}

# Error handler
trap 'error "Backup failed with error on line $LINENO"' ERR

# Run main function
main "$@"