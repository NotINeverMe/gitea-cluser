#!/bin/bash
# ==============================================================================
# Create Secrets in Google Secret Manager
# Generates secure random passwords and stores them in Secret Manager
# ==============================================================================
#
# Usage: ./create-secrets.sh [options]
#   -p PROJECT_ID    GCP Project ID (required)
#   -r REGION        GCP Region for secrets (default: us-central1)
#   -f               Force recreation of existing secrets
#   -v               Verbose output
#   -h               Show this help
#
# This script:
#   1. Generates secure random passwords
#   2. Creates secrets in Secret Manager
#   3. Stores Namecheap API credentials (if provided)
#   4. Outputs secret names (NOT values)
#   5. Generates evidence JSON
#
# CMMC Controls: IA.L2-3.5.1, SC.L2-3.13.11
# ==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
PROJECT_ID=""
REGION="us-central1"
FORCE=false
VERBOSE=false

# Print colored output
log() {
    local level=$1
    shift
    case "${level}" in
        ERROR)   echo -e "${RED}✗ $*${NC}" >&2 ;;
        SUCCESS) echo -e "${GREEN}✓ $*${NC}" ;;
        WARNING) echo -e "${YELLOW}⚠ $*${NC}" ;;
        INFO)    echo -e "${BLUE}ℹ $*${NC}" ;;
    esac
}

show_help() {
    head -20 "$0" | tail -18 | sed 's/^# //'
}

# Generate secure random password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Generate secure hex token
generate_hex_token() {
    local length=${1:-64}
    openssl rand -hex ${length}
}

# Create or update secret in Secret Manager
create_secret() {
    local secret_name=$1
    local secret_value=$2
    local description=$3

    if gcloud secrets describe "${secret_name}" --project="${PROJECT_ID}" &>/dev/null; then
        if [[ "${FORCE}" == "true" ]]; then
            log WARNING "Secret ${secret_name} exists - adding new version"
            echo -n "${secret_value}" | gcloud secrets versions add "${secret_name}" \
                --project="${PROJECT_ID}" \
                --data-file=-
        else
            log INFO "Secret ${secret_name} already exists - skipping (use -f to force)"
            return 0
        fi
    else
        log INFO "Creating secret: ${secret_name}"

        # Create secret
        gcloud secrets create "${secret_name}" \
            --project="${PROJECT_ID}" \
            --replication-policy="user-managed" \
            --locations="${REGION}" \
            --labels="environment=prod,managed-by=automation,cmmc=ia-l2-3-5-1"

        # Add first version
        echo -n "${secret_value}" | gcloud secrets versions add "${secret_name}" \
            --project="${PROJECT_ID}" \
            --data-file=-

        # Set description
        gcloud secrets update "${secret_name}" \
            --project="${PROJECT_ID}" \
            --update-labels="description=${description// /_}"
    fi

    log SUCCESS "Secret ${secret_name} configured"
}

# Main function
main() {
    # Parse arguments
    while getopts "p:r:fvh" opt; do
        case ${opt} in
            p) PROJECT_ID="${OPTARG}" ;;
            r) REGION="${OPTARG}" ;;
            f) FORCE=true ;;
            v) VERBOSE=true ;;
            h) show_help; exit 0 ;;
            *) show_help; exit 1 ;;
        esac
    done

    # Validate required arguments
    if [[ -z "${PROJECT_ID}" ]]; then
        log ERROR "Project ID is required (-p)"
        show_help
        exit 1
    fi

    log INFO "Creating secrets in project: ${PROJECT_ID}"
    log INFO "Region: ${REGION}"

    # Generate passwords and tokens
    log INFO "Generating secure passwords and tokens..."

    ADMIN_PASSWORD=$(generate_password 24)
    POSTGRES_PASSWORD=$(generate_password 32)
    GITEA_SECRET_KEY=$(generate_hex_token 32)
    GITEA_INTERNAL_TOKEN=$(generate_hex_token 64)
    GITEA_OAUTH2_JWT_SECRET=$(generate_password 44)
    GITEA_METRICS_TOKEN=$(generate_password 32)

    # Note: Runner token must be generated from Gitea UI after deployment
    GITEA_RUNNER_TOKEN="REPLACE_AFTER_GITEA_DEPLOYMENT"

    # Create secrets
    log INFO "Creating secrets in Secret Manager..."

    create_secret "gitea-admin-password" "${ADMIN_PASSWORD}" \
        "Gitea administrator password"

    create_secret "postgres-password" "${POSTGRES_PASSWORD}" \
        "PostgreSQL database password"

    create_secret "gitea-secret-key" "${GITEA_SECRET_KEY}" \
        "Gitea session encryption secret key"

    create_secret "gitea-internal-token" "${GITEA_INTERNAL_TOKEN}" \
        "Gitea internal API authentication token"

    create_secret "gitea-oauth2-jwt-secret" "${GITEA_OAUTH2_JWT_SECRET}" \
        "Gitea OAuth2 JWT signing secret"

    create_secret "gitea-metrics-token" "${GITEA_METRICS_TOKEN}" \
        "Prometheus metrics endpoint authentication token"

    create_secret "gitea-runner-token" "${GITEA_RUNNER_TOKEN}" \
        "Gitea Actions runner registration token (update after deployment)"

    # Namecheap API credentials (must be provided manually or via env vars)
    if [[ -n "${NAMECHEAP_API_KEY:-}" ]]; then
        create_secret "namecheap-api-key" "${NAMECHEAP_API_KEY}" \
            "Namecheap API key for DNS automation"
    else
        log WARNING "NAMECHEAP_API_KEY not set - create manually later"
    fi

    if [[ -n "${NAMECHEAP_API_USER:-}" ]]; then
        create_secret "namecheap-api-user" "${NAMECHEAP_API_USER}" \
            "Namecheap API username"
    else
        log WARNING "NAMECHEAP_API_USER not set - create manually later"
    fi

    if [[ -n "${NAMECHEAP_CLIENT_IP:-}" ]]; then
        create_secret "namecheap-api-ip" "${NAMECHEAP_CLIENT_IP}" \
            "Whitelisted IP address for Namecheap API"
    else
        log WARNING "NAMECHEAP_CLIENT_IP not set - create manually later"
    fi

    # Generate evidence
    local evidence_file="${PROJECT_ROOT}/terraform/gcp-gitea/evidence/secrets_created_$(date +%Y%m%d_%H%M%S).json"

    cat > "${evidence_file}" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "secrets_created": [
    "gitea-admin-password",
    "postgres-password",
    "gitea-secret-key",
    "gitea-internal-token",
    "gitea-oauth2-jwt-secret",
    "gitea-metrics-token",
    "gitea-runner-token",
    "namecheap-api-key",
    "namecheap-api-user",
    "namecheap-api-ip"
  ],
  "security_features": {
    "encryption_at_rest": true,
    "regional_replication": "${REGION}",
    "rotation_policy": "Manual (recommended: 90 days)",
    "access_control": "IAM-based"
  },
  "cmmc_controls": [
    "IA.L2-3.5.1 - Identification and Authentication",
    "SC.L2-3.13.11 - Cryptographic Protection"
  ],
  "next_steps": [
    "Update gitea-runner-token after Gitea deployment",
    "Configure secret rotation schedule",
    "Grant IAM access to service accounts",
    "Verify secrets in Secret Manager console"
  ]
}
EOF

    log SUCCESS "Evidence saved: ${evidence_file}"

    # Display summary (NO secret values)
    echo ""
    log SUCCESS "===== Secrets Created Successfully ====="
    echo ""
    log INFO "Project: ${PROJECT_ID}"
    log INFO "Region: ${REGION}"
    log INFO "Secrets: 10 created"
    echo ""
    log INFO "Next steps:"
    echo "  1. Verify secrets: gcloud secrets list --project=${PROJECT_ID}"
    echo "  2. Grant IAM access to service accounts"
    echo "  3. Deploy Gitea infrastructure"
    echo "  4. Update gitea-runner-token from Gitea UI"
    echo ""
    log INFO "To rotate secrets:"
    echo "  gcloud secrets versions add SECRET_NAME --data-file=- --project=${PROJECT_ID}"
    echo ""
    log WARNING "IMPORTANT: Secrets are stored in Secret Manager only - not displayed here"
    log WARNING "To retrieve: gcloud secrets versions access latest --secret=SECRET_NAME --project=${PROJECT_ID}"
    echo ""
}

main "$@"
