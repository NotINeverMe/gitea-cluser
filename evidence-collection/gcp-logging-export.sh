#!/bin/bash
# GCP Cloud Logging Export Automation
# Exports audit logs, admin activity, and data access logs for compliance evidence

set -euo pipefail

# Configuration
SCRIPT_DIR="/home/notme/Desktop/gitea/evidence-collection"
CONFIG_FILE="${SCRIPT_DIR}/config/evidence-config.yaml"
OUTPUT_DIR="${SCRIPT_DIR}/output/logging"
LOG_FILE="${SCRIPT_DIR}/logs/gcp-logging-export.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        GCP_PROJECT=$(yq eval '.gcp_project_id' "$CONFIG_FILE" 2>/dev/null || echo "your-project-id")
        GCS_BUCKET=$(yq eval '.gcs_bucket' "$CONFIG_FILE" 2>/dev/null || echo "evidence-collection-bucket")
        SERVICE_ACCOUNT_PATH=$(yq eval '.service_account_path' "$CONFIG_FILE" 2>/dev/null || echo "")
    else
        log "WARN: Config file not found, using defaults"
        GCP_PROJECT="your-project-id"
        GCS_BUCKET="evidence-collection-bucket"
        SERVICE_ACCOUNT_PATH=""
    fi
}

# Authenticate with service account
authenticate() {
    if [ -n "$SERVICE_ACCOUNT_PATH" ] && [ -f "$SERVICE_ACCOUNT_PATH" ]; then
        log "Authenticating with service account: $SERVICE_ACCOUNT_PATH"
        gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_PATH" || error_exit "Authentication failed"
        gcloud config set project "$GCP_PROJECT" || error_exit "Failed to set project"
    else
        log "Using default credentials"
    fi
}

# Create log sink for continuous export
create_log_sink() {
    local sink_name=$1
    local filter=$2
    local destination=$3

    log "Creating log sink: $sink_name"

    if gcloud logging sinks describe "$sink_name" --project="$GCP_PROJECT" &>/dev/null; then
        log "Sink $sink_name already exists, updating..."
        gcloud logging sinks update "$sink_name" \
            "$destination" \
            --log-filter="$filter" \
            --project="$GCP_PROJECT" || error_exit "Failed to update sink $sink_name"
    else
        gcloud logging sinks create "$sink_name" \
            "$destination" \
            --log-filter="$filter" \
            --project="$GCP_PROJECT" || error_exit "Failed to create sink $sink_name"
    fi

    log "Sink $sink_name configured successfully"
}

# Export admin activity logs (365-day retention)
export_admin_activity_logs() {
    log "Configuring admin activity log export..."

    local sink_name="admin-activity-evidence-sink"
    local destination="storage.googleapis.com/${GCS_BUCKET}/admin-activity-logs"
    local filter='protoPayload.serviceName=~".*googleapis.com" AND logName=~"logs/cloudaudit.googleapis.com%2Factivity"'

    create_log_sink "$sink_name" "$filter" "$destination"
}

# Export data access logs (90-day retention per regulation)
export_data_access_logs() {
    log "Configuring data access log export..."

    local sink_name="data-access-evidence-sink"
    local destination="storage.googleapis.com/${GCS_BUCKET}/data-access-logs"
    local filter='protoPayload.serviceName=~".*googleapis.com" AND logName=~"logs/cloudaudit.googleapis.com%2Fdata_access"'

    create_log_sink "$sink_name" "$filter" "$destination"
}

# Export system event logs
export_system_event_logs() {
    log "Configuring system event log export..."

    local sink_name="system-event-evidence-sink"
    local destination="storage.googleapis.com/${GCS_BUCKET}/system-event-logs"
    local filter='protoPayload.serviceName=~".*googleapis.com" AND logName=~"logs/cloudaudit.googleapis.com%2Fsystem_event"'

    create_log_sink "$sink_name" "$filter" "$destination"
}

# Export security audit logs
export_security_audit_logs() {
    log "Configuring security audit log export..."

    local sink_name="security-audit-evidence-sink"
    local destination="storage.googleapis.com/${GCS_BUCKET}/security-audit-logs"
    local filter='(protoPayload.serviceName="iam.googleapis.com" OR protoPayload.serviceName="cloudkms.googleapis.com" OR protoPayload.serviceName="securitycenter.googleapis.com") AND severity>="WARNING"'

    create_log_sink "$sink_name" "$filter" "$destination"
}

# Export logs for specific time range (one-time export)
export_historical_logs() {
    local log_filter=$1
    local start_time=$2
    local end_time=$3
    local output_file=$4

    log "Exporting historical logs: $output_file"

    gcloud logging read "$log_filter" \
        --project="$GCP_PROJECT" \
        --format=json \
        --freshness="${start_time}" \
        --order=desc \
        --limit=10000 > "${OUTPUT_DIR}/${output_file}" || error_exit "Failed to export historical logs"

    # Generate hash
    local hash=$(sha256sum "${OUTPUT_DIR}/${output_file}" | awk '{print $1}')
    echo "$hash" > "${OUTPUT_DIR}/${output_file}.sha256"

    log "Historical logs saved to ${OUTPUT_DIR}/${output_file} (SHA-256: $hash)"
}

# Configure GCS bucket lifecycle for retention
configure_retention_policy() {
    log "Configuring GCS bucket retention policy..."

    # Create lifecycle configuration
    cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 2555,
          "matchesPrefix": ["admin-activity-logs/"]
        }
      },
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 90,
          "matchesPrefix": ["data-access-logs/"]
        }
      },
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 2555,
          "matchesPrefix": ["system-event-logs/", "security-audit-logs/"]
        }
      }
    ]
  }
}
EOF

    gsutil lifecycle set /tmp/lifecycle.json "gs://${GCS_BUCKET}" || log "WARN: Failed to set lifecycle policy"
    rm /tmp/lifecycle.json
}

# Enable bucket versioning and retention lock
configure_bucket_immutability() {
    log "Configuring bucket immutability (WORM)..."

    # Enable versioning
    gsutil versioning set on "gs://${GCS_BUCKET}" || log "WARN: Failed to enable versioning"

    # Set retention policy (7 years for critical evidence)
    gsutil retention set 7y "gs://${GCS_BUCKET}" || log "WARN: Failed to set retention policy"

    # Note: Retention lock should be applied manually with confirmation
    log "MANUAL STEP REQUIRED: Lock retention policy with: gsutil retention lock gs://${GCS_BUCKET}"
}

# Generate evidence manifest
generate_manifest() {
    log "Generating evidence manifest..."

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local manifest_file="${OUTPUT_DIR}/logging_export_manifest_$(date -u +'%Y%m%d_%H%M%S').json"

    cat > "$manifest_file" <<EOF
{
  "evidence_type": "gcp_cloud_logging_export",
  "collection_timestamp": "$timestamp",
  "gcp_project": "$GCP_PROJECT",
  "gcs_bucket": "gs://${GCS_BUCKET}",
  "log_sinks": [
    {
      "name": "admin-activity-evidence-sink",
      "destination": "storage.googleapis.com/${GCS_BUCKET}/admin-activity-logs",
      "retention_days": 2555,
      "control_ids": ["AU.L2-3.3.1", "AU.L2-3.3.2", "AU.L2-3.3.3", "AU.L2-3.3.5"]
    },
    {
      "name": "data-access-evidence-sink",
      "destination": "storage.googleapis.com/${GCS_BUCKET}/data-access-logs",
      "retention_days": 90,
      "control_ids": ["AU.L2-3.3.1", "AU.L2-3.3.2", "AU.L2-3.3.6"]
    },
    {
      "name": "system-event-evidence-sink",
      "destination": "storage.googleapis.com/${GCS_BUCKET}/system-event-logs",
      "retention_days": 2555,
      "control_ids": ["AU.L2-3.3.1", "AU.L2-3.3.2", "SI.L2-3.14.6"]
    },
    {
      "name": "security-audit-evidence-sink",
      "destination": "storage.googleapis.com/${GCS_BUCKET}/security-audit-logs",
      "retention_days": 2555,
      "control_ids": ["AU.L2-3.3.1", "AU.L2-3.3.2", "AU.L2-3.3.4", "IA.L2-3.5.3"]
    }
  ],
  "control_framework": "CMMC_2.0",
  "collector_version": "1.0.0"
}
EOF

    log "Manifest saved to $manifest_file"
}

# Main execution
main() {
    log "=== Starting GCP Cloud Logging Export ==="

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Load configuration
    load_config

    # Authenticate
    authenticate

    # Create log sinks for continuous export
    export_admin_activity_logs
    export_data_access_logs
    export_system_event_logs
    export_security_audit_logs

    # Configure retention and immutability
    configure_retention_policy
    configure_bucket_immutability

    # Generate manifest
    generate_manifest

    log "=== GCP Cloud Logging Export completed successfully ==="
}

# Execute main function
main "$@"
