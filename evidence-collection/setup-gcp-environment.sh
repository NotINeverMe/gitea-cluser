#!/bin/bash
# GCP Environment Setup Script
# Configures GCP project for evidence collection

set -euo pipefail

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

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found. Please install: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Get project configuration
echo "=== GCP Evidence Collection Environment Setup ==="
echo ""

read -p "Enter GCP Project ID: " PROJECT_ID
read -p "Enter GCP Organization ID (or press enter to skip): " ORG_ID
read -p "Enter service account name [evidence-collector]: " SA_NAME
SA_NAME=${SA_NAME:-evidence-collector}

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

log_info "Configuration:"
log_info "  Project ID: ${PROJECT_ID}"
log_info "  Organization ID: ${ORG_ID:-N/A}"
log_info "  Service Account: ${SA_EMAIL}"
echo ""

read -p "Proceed with setup? (y/n): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    log_warn "Setup cancelled"
    exit 0
fi

# Set active project
log_info "Setting active project to ${PROJECT_ID}..."
gcloud config set project ${PROJECT_ID}

# Enable required APIs
log_info "Enabling required GCP APIs..."
APIS=(
    "securitycenter.googleapis.com"
    "cloudasset.googleapis.com"
    "logging.googleapis.com"
    "iam.googleapis.com"
    "cloudkms.googleapis.com"
    "compute.googleapis.com"
    "storage.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)

for API in "${APIS[@]}"; do
    log_info "  Enabling ${API}..."
    gcloud services enable ${API} --project=${PROJECT_ID} || log_warn "    Failed to enable ${API}"
done

# Create service account
log_info "Creating service account: ${SA_NAME}..."
if gcloud iam service-accounts describe ${SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
    log_warn "Service account ${SA_EMAIL} already exists, skipping creation"
else
    gcloud iam service-accounts create ${SA_NAME} \
        --display-name="Evidence Collection Service Account" \
        --description="Automated evidence collection for CMMC compliance" \
        --project=${PROJECT_ID}
fi

# Grant IAM roles
log_info "Granting IAM roles to service account..."

ROLES=(
    "roles/securitycenter.findingsViewer"
    "roles/cloudasset.viewer"
    "roles/logging.viewer"
    "roles/iam.securityReviewer"
    "roles/cloudkms.viewer"
    "roles/storage.objectCreator"
    "roles/compute.viewer"
)

for ROLE in "${ROLES[@]}"; do
    log_info "  Granting ${ROLE}..."
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="${ROLE}" \
        --condition=None \
        --quiet || log_warn "    Failed to grant ${ROLE}"
done

# Create service account key
log_info "Creating service account key..."
KEY_FILE="config/gcp-service-account.json"

if [ -f "${KEY_FILE}" ]; then
    log_warn "Key file ${KEY_FILE} already exists"
    read -p "Overwrite existing key? (y/n): " OVERWRITE
    if [[ ! $OVERWRITE =~ ^[Yy]$ ]]; then
        log_warn "Skipping key creation"
    else
        gcloud iam service-accounts keys create ${KEY_FILE} \
            --iam-account=${SA_EMAIL} \
            --project=${PROJECT_ID}
        log_info "Service account key saved to ${KEY_FILE}"
    fi
else
    mkdir -p config
    gcloud iam service-accounts keys create ${KEY_FILE} \
        --iam-account=${SA_EMAIL} \
        --project=${PROJECT_ID}
    log_info "Service account key saved to ${KEY_FILE}"
fi

# Create GCS bucket for evidence storage
BUCKET_NAME="evidence-${PROJECT_ID}"
log_info "Creating GCS bucket: gs://${BUCKET_NAME}..."

if gsutil ls gs://${BUCKET_NAME} &>/dev/null; then
    log_warn "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
else
    gsutil mb -p ${PROJECT_ID} -l us-central1 -b on gs://${BUCKET_NAME}/
    log_info "Bucket created: gs://${BUCKET_NAME}"
fi

# Configure bucket settings
log_info "Configuring bucket settings..."

# Enable versioning
gsutil versioning set on gs://${BUCKET_NAME}/
log_info "  Versioning enabled"

# Set retention policy (7 years)
gsutil retention set 7y gs://${BUCKET_NAME}/
log_info "  Retention policy set to 7 years"

# Enable uniform bucket-level access
gsutil uniformbucketlevelaccess set on gs://${BUCKET_NAME}/
log_info "  Uniform bucket-level access enabled"

# Set lifecycle policy
log_info "Setting lifecycle policy..."
cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 2555,
          "matchesPrefix": ["admin-activity-logs/", "security-audit-logs/", "scc-findings/"]
        }
      },
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "matchesPrefix": ["data-access-logs/"]
        }
      }
    ]
  }
}
EOF

gsutil lifecycle set /tmp/lifecycle.json gs://${BUCKET_NAME}/
rm /tmp/lifecycle.json
log_info "  Lifecycle policy configured"

# Grant service account access to bucket
log_info "Granting service account access to bucket..."
gsutil iam ch serviceAccount:${SA_EMAIL}:roles/storage.objectCreator gs://${BUCKET_NAME}/
gsutil iam ch serviceAccount:${SA_EMAIL}:roles/storage.objectViewer gs://${BUCKET_NAME}/

# Update configuration file
log_info "Updating evidence-config.yaml..."
if [ -f "config/evidence-config.yaml" ]; then
    # Update existing config
    sed -i.bak "s/gcp_project_id: .*/gcp_project_id: \"${PROJECT_ID}\"/" config/evidence-config.yaml
    sed -i.bak "s/gcs_bucket: .*/gcs_bucket: \"${BUCKET_NAME}\"/" config/evidence-config.yaml

    if [ -n "${ORG_ID}" ]; then
        sed -i.bak "s|gcp_organization_id: .*|gcp_organization_id: \"${ORG_ID}\"|" config/evidence-config.yaml
    fi

    log_info "Configuration file updated"
else
    log_warn "config/evidence-config.yaml not found, please update manually"
fi

# Summary
echo ""
log_info "=== Setup Complete ==="
log_info ""
log_info "GCP Project: ${PROJECT_ID}"
log_info "Service Account: ${SA_EMAIL}"
log_info "GCS Bucket: gs://${BUCKET_NAME}"
log_info "Service Account Key: ${KEY_FILE}"
log_info ""
log_info "Next steps:"
log_info "  1. Review and update config/evidence-config.yaml"
log_info "  2. Test collectors: python3 gcp-scc-collector.py --config config/evidence-config.yaml"
log_info "  3. Review GCP_EVIDENCE_COLLECTION_GUIDE.md for detailed instructions"
log_info ""
log_warn "IMPORTANT: Lock bucket retention policy in production:"
log_warn "  gsutil retention lock gs://${BUCKET_NAME}/"
log_warn "  (This is IRREVERSIBLE - test thoroughly first!)"
echo ""
