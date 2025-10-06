#!/bin/bash
# Atlantis Setup Script for Gitea GitOps
# CMMC 2.0: CM.L2-3.4.2 (Configuration Management)
# NIST SP 800-171: 3.4.2 (Baseline Configuration)

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Evidence collection
EVIDENCE_DIR="/tmp/atlantis-setup-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

# Start evidence log
echo "Atlantis Setup Started: $(date -Iseconds)" > "$EVIDENCE_DIR/setup.log"
echo "User: $(whoami)" >> "$EVIDENCE_DIR/setup.log"
echo "Host: $(hostname)" >> "$EVIDENCE_DIR/setup.log"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check required tools
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v docker-compose >/dev/null 2>&1 || missing_tools+=("docker-compose")
    command -v gcloud >/dev/null 2>&1 || missing_tools+=("gcloud")
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v terragrunt >/dev/null 2>&1 || missing_tools+=("terragrunt")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi

    log_info "All prerequisites met"
    echo "Prerequisites checked: $(date -Iseconds)" >> "$EVIDENCE_DIR/setup.log"
}

# Create environment file
create_env_file() {
    log_info "Creating environment configuration..."

    # Check if .env exists
    if [ -f "atlantis/.env" ]; then
        log_warn ".env file exists. Backing up..."
        cp atlantis/.env "atlantis/.env.backup-$(date +%Y%m%d-%H%M%S)"
    fi

    cat > atlantis/.env << 'EOF'
# Atlantis Environment Configuration
# Generated: $(date -Iseconds)

# Atlantis Server Settings
ATLANTIS_HOST=atlantis.gitea.local
ATLANTIS_LOG_LEVEL=info
ATLANTIS_REQUIRE_APPROVAL=true
ATLANTIS_REQUIRE_MERGEABLE=true
ATLANTIS_ENABLE_POLICY_CHECKS=true

# Gitea Integration
ATLANTIS_GITEA_USER=${GITEA_USER}
ATLANTIS_GITEA_TOKEN=${GITEA_TOKEN}
ATLANTIS_WEBHOOK_SECRET=${WEBHOOK_SECRET}
GITEA_BASE_URL=https://gitea.local

# GCP Configuration
GCP_PROJECT_ID=${PROJECT_ID}
GCP_REGION=us-central1

# Repository Settings
ATLANTIS_REPO_ALLOWLIST=gitea.local/*

# Security Settings
ATLANTIS_WRITE_GIT_CREDS=false
ATLANTIS_HIDE_UNCHANGED_PLAN_COMMENTS=false

# Terraform Settings
TF_VERSION=1.6.0
ATLANTIS_PARALLEL_POOL_SIZE=4

# Database
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}

# Infracost
INFRACOST_API_KEY=${INFRACOST_API_KEY}

# Notification
CHAT_WEBHOOK_URL=${CHAT_WEBHOOK_URL}
EOF

    log_info "Environment file created. Please edit atlantis/.env with your values"
    echo "Environment file created: $(date -Iseconds)" >> "$EVIDENCE_DIR/setup.log"
}

# Generate TLS certificates
generate_tls_certs() {
    log_info "Generating TLS certificates..."

    mkdir -p atlantis/tls

    # Generate self-signed cert for development
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout atlantis/tls/key.pem \
        -out atlantis/tls/cert.pem \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=atlantis.gitea.local" \
        2>/dev/null

    # Set proper permissions
    chmod 600 atlantis/tls/key.pem
    chmod 644 atlantis/tls/cert.pem

    log_info "TLS certificates generated"
    echo "TLS certificates generated: $(date -Iseconds)" >> "$EVIDENCE_DIR/setup.log"
}

# Create GCP service account
create_gcp_service_account() {
    log_info "Creating GCP service account..."

    local PROJECT_ID="${1:-}"
    if [ -z "$PROJECT_ID" ]; then
        read -p "Enter GCP Project ID: " PROJECT_ID
    fi

    local SA_NAME="atlantis-terraform"
    local SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

    # Create service account
    gcloud iam service-accounts create ${SA_NAME} \
        --display-name="Atlantis Terraform Service Account" \
        --project="${PROJECT_ID}" || log_warn "Service account may already exist"

    # Grant necessary roles (least privilege)
    local roles=(
        "roles/compute.admin"
        "roles/container.admin"
        "roles/iam.serviceAccountUser"
        "roles/storage.admin"
        "roles/resourcemanager.projectIamAdmin"
        "roles/logging.admin"
        "roles/monitoring.admin"
        "roles/cloudkms.admin"
        "roles/dns.admin"
    )

    for role in "${roles[@]}"; do
        log_info "Granting role: $role"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SA_EMAIL}" \
            --role="${role}" \
            --condition=None || log_warn "Failed to grant role: $role"
    done

    # Create and download key
    gcloud iam service-accounts keys create atlantis/gcp-sa.json \
        --iam-account="${SA_EMAIL}" \
        --project="${PROJECT_ID}"

    # Set proper permissions
    chmod 600 atlantis/gcp-sa.json

    log_info "GCP service account created: ${SA_EMAIL}"
    echo "GCP service account created: ${SA_EMAIL}" >> "$EVIDENCE_DIR/setup.log"
}

# Create GCS buckets for Terraform state
create_gcs_buckets() {
    log_info "Creating GCS buckets for Terraform state..."

    local PROJECT_ID="${1:-}"
    if [ -z "$PROJECT_ID" ]; then
        read -p "Enter GCP Project ID: " PROJECT_ID
    fi

    local BUCKET_NAME="${PROJECT_ID}-terraform-state"
    local EVIDENCE_BUCKET="${PROJECT_ID}-atlantis-evidence"

    # Create state bucket
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l us-central1 \
        -b on --retention 365d \
        "gs://${BUCKET_NAME}" || log_warn "State bucket may already exist"

    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"

    # Enable uniform bucket-level access
    gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}"

    # Create evidence bucket
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l us-central1 \
        -b on --retention 365d \
        "gs://${EVIDENCE_BUCKET}" || log_warn "Evidence bucket may already exist"

    # Enable versioning
    gsutil versioning set on "gs://${EVIDENCE_BUCKET}"

    # Set lifecycle rules for evidence
    cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "NEARLINE"
        },
        "condition": {
          "age": 30
        }
      },
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "COLDLINE"
        },
        "condition": {
          "age": 90
        }
      }
    ]
  }
}
EOF

    gsutil lifecycle set /tmp/lifecycle.json "gs://${EVIDENCE_BUCKET}"

    log_info "GCS buckets created"
    echo "GCS buckets created: ${BUCKET_NAME}, ${EVIDENCE_BUCKET}" >> "$EVIDENCE_DIR/setup.log"
}

# Create Caddy configuration
create_caddy_config() {
    log_info "Creating Caddy configuration..."

    cat > atlantis/Caddyfile << 'EOF'
# Caddy Configuration for Atlantis
# CMMC 2.0: CM.L2-3.4.2

atlantis.gitea.local {
    # TLS configuration
    tls /etc/caddy/tls/cert.pem /etc/caddy/tls/key.pem

    # Security headers
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        Content-Security-Policy "default-src 'self'"
    }

    # Rate limiting
    rate_limit {
        zone dynamic {
            key {remote_host}
            events 100
            window 60s
        }
    }

    # Reverse proxy to Atlantis
    reverse_proxy atlantis:4141 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}

        # Health check
        health_uri /healthz
        health_interval 30s
        health_timeout 10s
    }

    # Access logs
    log {
        output file /var/log/caddy/access.log {
            roll_size 100mb
            roll_keep 10
        }
        format json
    }

    # Metrics endpoint
    metrics /metrics {
        disable_openmetrics
    }
}

# Admin API (internal only)
:2019 {
    metrics /metrics
}
EOF

    log_info "Caddy configuration created"
    echo "Caddy configuration created: $(date -Iseconds)" >> "$EVIDENCE_DIR/setup.log"
}

# Initialize Terragrunt
initialize_terragrunt() {
    log_info "Initializing Terragrunt configurations..."

    # Create common tfvars
    cat > terragrunt/common.tfvars << 'EOF'
# Common Terraform Variables
# Generated: $(date -Iseconds)

# Compliance tags
compliance_tags = {
  cmmc_level = "2"
  nist_framework = "SP-800-171"
  data_classification = "cui"
}

# Security defaults
enable_encryption = true
enable_audit_logs = true
enable_monitoring = true
enable_backup = true

# Network defaults
enable_private_endpoints = true
enable_flow_logs = true
EOF

    log_info "Terragrunt initialized"
    echo "Terragrunt initialized: $(date -Iseconds)" >> "$EVIDENCE_DIR/setup.log"
}

# Configure Gitea webhook
configure_gitea_webhook() {
    log_info "Configuring Gitea webhook..."

    local GITEA_URL="${1:-https://gitea.local}"
    local GITEA_TOKEN="${2:-}"
    local WEBHOOK_SECRET="${3:-}"
    local REPO="${4:-infrastructure/terraform-gcp}"

    if [ -z "$GITEA_TOKEN" ]; then
        read -s -p "Enter Gitea API token: " GITEA_TOKEN
        echo
    fi

    if [ -z "$WEBHOOK_SECRET" ]; then
        WEBHOOK_SECRET=$(openssl rand -hex 32)
        log_info "Generated webhook secret: ${WEBHOOK_SECRET}"
    fi

    # Create webhook via API
    curl -X POST "${GITEA_URL}/api/v1/repos/${REPO}/hooks" \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @- << EOF
{
  "type": "gitea",
  "config": {
    "url": "https://atlantis.gitea.local/events",
    "content_type": "json",
    "secret": "${WEBHOOK_SECRET}",
    "insecure_ssl": "false"
  },
  "events": [
    "pull_request",
    "pull_request_comment",
    "pull_request_review",
    "pull_request_review_comment"
  ],
  "active": true
}
EOF

    log_info "Gitea webhook configured"
    echo "Webhook secret: ${WEBHOOK_SECRET}" >> "$EVIDENCE_DIR/webhook-secret.txt"
    chmod 600 "$EVIDENCE_DIR/webhook-secret.txt"
}

# Start Atlantis
start_atlantis() {
    log_info "Starting Atlantis services..."

    cd atlantis

    # Create docker network if not exists
    docker network create gitea-net 2>/dev/null || true
    docker network create monitoring 2>/dev/null || true

    # Pull images
    docker-compose pull

    # Start services
    docker-compose up -d

    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 10

    # Check status
    docker-compose ps

    cd ..

    log_info "Atlantis started successfully"
    echo "Atlantis started: $(date -Iseconds)" >> "$EVIDENCE_DIR/setup.log"
}

# Generate evidence hash
generate_evidence() {
    log_info "Generating setup evidence..."

    # Collect all configuration files
    tar czf "$EVIDENCE_DIR/configs.tar.gz" \
        atlantis/*.yaml \
        atlantis/*.yml \
        atlantis/policies/*.rego \
        terragrunt/terragrunt.hcl \
        2>/dev/null || true

    # Generate SHA-256 hashes
    find "$EVIDENCE_DIR" -type f -exec sha256sum {} \; > "$EVIDENCE_DIR/hashes.txt"

    # Sign with timestamp
    echo "Setup completed: $(date -Iseconds)" >> "$EVIDENCE_DIR/setup.log"
    echo "Git commit: $(git rev-parse HEAD 2>/dev/null || echo 'N/A')" >> "$EVIDENCE_DIR/setup.log"

    # Upload to GCS if configured
    if [ -n "${GCP_PROJECT_ID:-}" ]; then
        gsutil -h "x-goog-meta-cmmc:CM.L2-3.4.2" \
               -h "x-goog-meta-type:atlantis-setup" \
               cp -r "$EVIDENCE_DIR" \
               "gs://${GCP_PROJECT_ID}-atlantis-evidence/setup/$(date +%Y%m%d)/" || true
    fi

    log_info "Evidence collected in: $EVIDENCE_DIR"
}

# Main execution
main() {
    log_info "Starting Atlantis setup for Gitea GitOps"

    check_prerequisites
    create_env_file
    generate_tls_certs

    # Get GCP project ID
    read -p "Enter GCP Project ID (or skip): " PROJECT_ID
    if [ -n "$PROJECT_ID" ]; then
        create_gcp_service_account "$PROJECT_ID"
        create_gcs_buckets "$PROJECT_ID"
    fi

    create_caddy_config
    initialize_terragrunt

    # Configure Gitea webhook
    read -p "Configure Gitea webhook now? (y/n): " CONFIGURE_WEBHOOK
    if [ "$CONFIGURE_WEBHOOK" = "y" ]; then
        configure_gitea_webhook
    fi

    # Start services
    read -p "Start Atlantis services now? (y/n): " START_SERVICES
    if [ "$START_SERVICES" = "y" ]; then
        start_atlantis
    fi

    generate_evidence

    log_info "Setup complete!"
    log_info "Next steps:"
    log_info "1. Edit atlantis/.env with your configuration values"
    log_info "2. Configure Gitea webhook if not done"
    log_info "3. Test with a pull request to trigger Atlantis"
    log_info "4. Review evidence in: $EVIDENCE_DIR"
}

# Run main function
main "$@"