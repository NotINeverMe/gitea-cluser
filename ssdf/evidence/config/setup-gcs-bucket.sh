#!/bin/bash
# GCS Bucket Setup Script for SSDF Evidence Storage
# Creates and configures GCS bucket with 7-year retention policy

set -euo pipefail

# Configuration
BUCKET_NAME="${GCS_EVIDENCE_BUCKET:-compliance-evidence-ssdf}"
LOG_BUCKET="${BUCKET_NAME}-logs"
PROJECT_ID="${GCP_PROJECT:-}"
LOCATION="${GCS_LOCATION:-us-central1}"
STORAGE_CLASS="STANDARD"
RETENTION_POLICY_FILE="$(dirname "$0")/../retention-policy.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi

    # Check gsutil
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil not found. Please install Google Cloud SDK."
        exit 1
    fi

    # Check if logged in
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated. Run: gcloud auth login"
        exit 1
    fi

    # Check project
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            log_error "GCP project not set. Set GCP_PROJECT environment variable or run: gcloud config set project PROJECT_ID"
            exit 1
        fi
    fi

    log_info "Using project: $PROJECT_ID"
    log_info "Using location: $LOCATION"
}

# Create main evidence bucket
create_evidence_bucket() {
    log_info "Creating evidence bucket: gs://$BUCKET_NAME"

    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        log_warn "Bucket gs://$BUCKET_NAME already exists"
    else
        gsutil mb \
            -p "$PROJECT_ID" \
            -c "$STORAGE_CLASS" \
            -l "$LOCATION" \
            "gs://$BUCKET_NAME"
        log_info "Bucket created successfully"
    fi
}

# Create logging bucket
create_log_bucket() {
    log_info "Creating logging bucket: gs://$LOG_BUCKET"

    if gsutil ls -b "gs://$LOG_BUCKET" &> /dev/null; then
        log_warn "Bucket gs://$LOG_BUCKET already exists"
    else
        gsutil mb \
            -p "$PROJECT_ID" \
            -c "$STORAGE_CLASS" \
            -l "$LOCATION" \
            "gs://$LOG_BUCKET"
        log_info "Logging bucket created successfully"
    fi
}

# Enable versioning
enable_versioning() {
    log_info "Enabling versioning on gs://$BUCKET_NAME"
    gsutil versioning set on "gs://$BUCKET_NAME"
    log_info "Versioning enabled"
}

# Set lifecycle policy
set_lifecycle_policy() {
    log_info "Setting lifecycle policy for 7-year retention"

    if [ ! -f "$RETENTION_POLICY_FILE" ]; then
        log_error "Retention policy file not found: $RETENTION_POLICY_FILE"
        exit 1
    fi

    gsutil lifecycle set "$RETENTION_POLICY_FILE" "gs://$BUCKET_NAME"
    log_info "Lifecycle policy applied"

    # Verify policy
    log_info "Verifying lifecycle policy:"
    gsutil lifecycle get "gs://$BUCKET_NAME"
}

# Enable logging
enable_logging() {
    log_info "Enabling access logging"
    gsutil logging set on \
        -b "gs://$LOG_BUCKET" \
        -o "access-logs/" \
        "gs://$BUCKET_NAME"
    log_info "Access logging enabled"
}

# Set bucket labels
set_labels() {
    log_info "Setting bucket labels"
    gsutil label ch \
        -l purpose:compliance-evidence \
        -l framework:ssdf \
        -l retention:7-years \
        -l environment:production \
        "gs://$BUCKET_NAME"
    log_info "Labels set successfully"
}

# Enable uniform bucket-level access
enable_uniform_access() {
    log_info "Enabling uniform bucket-level access"
    gsutil ub set on "gs://$BUCKET_NAME"
    log_info "Uniform bucket-level access enabled"
}

# Set CORS policy (empty - no web access)
set_cors_policy() {
    log_info "Setting CORS policy (blocking web access)"
    echo '[]' | gsutil cors set /dev/stdin "gs://$BUCKET_NAME"
    log_info "CORS policy set"
}

# Set default object ACL (private)
set_default_acl() {
    log_info "Setting default object ACL to private"
    gsutil defacl set private "gs://$BUCKET_NAME"
    log_info "Default ACL set to private"
}

# Create service account for evidence collector
create_service_account() {
    local SA_NAME="evidence-collector"
    local SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

    log_info "Creating service account: $SA_NAME"

    if gcloud iam service-accounts describe "$SA_EMAIL" &> /dev/null; then
        log_warn "Service account $SA_EMAIL already exists"
    else
        gcloud iam service-accounts create "$SA_NAME" \
            --display-name="SSDF Evidence Collector" \
            --description="Service account for collecting and storing compliance evidence" \
            --project="$PROJECT_ID"
        log_info "Service account created"
    fi

    # Grant bucket permissions
    log_info "Granting bucket permissions to service account"
    gsutil iam ch \
        "serviceAccount:${SA_EMAIL}:roles/storage.objectCreator" \
        "gs://$BUCKET_NAME"

    gsutil iam ch \
        "serviceAccount:${SA_EMAIL}:roles/storage.objectViewer" \
        "gs://$BUCKET_NAME"

    log_info "Service account configured"
    log_info "To create a key: gcloud iam service-accounts keys create key.json --iam-account=$SA_EMAIL"
}

# Set retention policy lock (WARNING: irreversible)
lock_retention_policy() {
    log_warn "RETENTION POLICY LOCKING IS IRREVERSIBLE"
    log_warn "This will enforce 7-year retention and prevent deletion before expiration"
    read -p "Are you sure you want to lock the retention policy? (yes/no): " -r
    echo

    if [[ $REPLY == "yes" ]]; then
        log_info "Locking retention policy (2555 days = 7 years)"
        gsutil retention set 220752000s "gs://$BUCKET_NAME"  # 2555 days in seconds
        gsutil retention lock "gs://$BUCKET_NAME"
        log_info "Retention policy locked"
    else
        log_info "Retention policy NOT locked (you can lock it later)"
    fi
}

# Display bucket info
show_bucket_info() {
    log_info "Bucket configuration summary:"
    echo ""
    gsutil ls -L -b "gs://$BUCKET_NAME"
    echo ""
    log_info "Setup complete!"
    log_info "Bucket: gs://$BUCKET_NAME"
    log_info "Logging: gs://$LOG_BUCKET"
    log_info "Retention: 7 years (2555 days)"
    log_info ""
    log_info "Next steps:"
    log_info "1. Create service account key: gcloud iam service-accounts keys create credentials.json --iam-account=evidence-collector@${PROJECT_ID}.iam.gserviceaccount.com"
    log_info "2. Set GOOGLE_APPLICATION_CREDENTIALS environment variable"
    log_info "3. Test access: gsutil ls gs://$BUCKET_NAME"
}

# Main execution
main() {
    log_info "Starting GCS bucket setup for SSDF evidence storage"
    log_info "=================================================="

    check_prerequisites
    create_evidence_bucket
    create_log_bucket
    enable_versioning
    set_lifecycle_policy
    enable_logging
    set_labels
    enable_uniform_access
    set_cors_policy
    set_default_acl
    create_service_account

    # Optional: Lock retention policy
    echo ""
    lock_retention_policy

    echo ""
    show_bucket_info
}

# Run main function
main
