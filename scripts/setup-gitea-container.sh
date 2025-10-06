#!/bin/bash

# Gitea Container Deployment Script
# Sets up containerized Gitea with PostgreSQL, Actions Runner, and integrations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Gitea Container Deployment - DevSecOps Platform        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    fi

    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi

    log_success "All dependencies found"
}

generate_secrets() {
    log_info "Generating secure secrets..."

    # Generate random secrets
    GITEA_SECRET_KEY=$(openssl rand -hex 32)
    GITEA_INTERNAL_TOKEN=$(openssl rand -hex 32)
    GITEA_OAUTH2_JWT_SECRET=$(openssl rand -hex 32)
    GITEA_METRICS_TOKEN=$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-32)
    POSTGRES_GITEA_PASSWORD=$(openssl rand -base64 32 | tr -d '=/+')
    ATLANTIS_WEBHOOK_SECRET=$(openssl rand -base64 32 | tr -d '=/+')
    N8N_API_KEY=$(openssl rand -base64 32 | tr -d '=/+')

    log_success "Secrets generated successfully"
}

create_env_file() {
    log_info "Creating .env.gitea configuration file..."

    cd "$PROJECT_DIR"

    if [ -f .env.gitea ]; then
        log_warning ".env.gitea already exists, creating backup..."
        cp .env.gitea ".env.gitea.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # Prompt for domain
    read -p "Enter your Gitea domain (default: localhost): " GITEA_DOMAIN
    GITEA_DOMAIN=${GITEA_DOMAIN:-localhost}

    # Determine protocol
    if [ "$GITEA_DOMAIN" = "localhost" ]; then
        GITEA_ROOT_URL="http://localhost:3000/"
        GITEA_COOKIE_SECURE="false"
    else
        GITEA_ROOT_URL="https://${GITEA_DOMAIN}/"
        GITEA_COOKIE_SECURE="true"
    fi

    # Prompt for admin credentials
    read -p "Enter admin username (default: admin): " GITEA_ADMIN_USER
    GITEA_ADMIN_USER=${GITEA_ADMIN_USER:-admin}

    read -s -p "Enter admin password (min 14 chars): " GITEA_ADMIN_PASSWORD
    echo ""
    if [ ${#GITEA_ADMIN_PASSWORD} -lt 14 ]; then
        log_error "Password must be at least 14 characters"
        exit 1
    fi

    read -p "Enter admin email: " GITEA_ADMIN_EMAIL

    # Prompt for GCP project
    read -p "Enter GCP project ID (optional): " GCP_PROJECT_ID

    # Create .env.gitea
    cat > .env.gitea <<EOF
# Gitea Container Configuration
# Generated on $(date)

# ============================================================================
# GITEA SERVER CONFIGURATION
# ============================================================================

GITEA_DOMAIN=${GITEA_DOMAIN}
GITEA_ROOT_URL=${GITEA_ROOT_URL}

GITEA_HTTP_PORT=3000
GITEA_SSH_PORT=2222
GITEA_HTTPS_PORT=443
GITEA_HTTP_REDIRECT_PORT=80

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================

POSTGRES_GITEA_PASSWORD=${POSTGRES_GITEA_PASSWORD}

# ============================================================================
# SECURITY CONFIGURATION
# ============================================================================

GITEA_SECRET_KEY=${GITEA_SECRET_KEY}
GITEA_INTERNAL_TOKEN=${GITEA_INTERNAL_TOKEN}
GITEA_OAUTH2_JWT_SECRET=${GITEA_OAUTH2_JWT_SECRET}
GITEA_METRICS_TOKEN=${GITEA_METRICS_TOKEN}

GITEA_ADMIN_USER=${GITEA_ADMIN_USER}
GITEA_ADMIN_PASSWORD=${GITEA_ADMIN_PASSWORD}
GITEA_ADMIN_EMAIL=${GITEA_ADMIN_EMAIL}

GITEA_DISABLE_REGISTRATION=false
GITEA_COOKIE_SECURE=${GITEA_COOKIE_SECURE}
GITEA_WEBHOOK_SKIP_TLS=false

# ============================================================================
# GITEA ACTIONS RUNNER CONFIGURATION
# ============================================================================

# Note: Generate runner token from Gitea UI after first startup
# Admin Panel → Actions → Runners → Create Registration Token
GITEA_RUNNER_TOKEN=REPLACE_AFTER_GITEA_STARTUP

# ============================================================================
# INTEGRATION TOKENS
# ============================================================================

N8N_WEBHOOK_URL=http://n8n:5678/webhook/security-events
N8N_API_KEY=${N8N_API_KEY}

ATLANTIS_URL=http://atlantis:4141
ATLANTIS_WEBHOOK_SECRET=${ATLANTIS_WEBHOOK_SECRET}

SONARQUBE_URL=http://sonarqube:9000
SONARQUBE_TOKEN=GENERATE_FROM_SONARQUBE_UI

# ============================================================================
# GCP CONFIGURATION
# ============================================================================

GCP_PROJECT_ID=${GCP_PROJECT_ID}
GCS_EVIDENCE_BUCKET=gs://compliance-evidence-${GCP_PROJECT_ID:-yourorg}
GCS_MANIFEST_BUCKET=gs://compliance-manifests-${GCP_PROJECT_ID:-yourorg}

# ============================================================================
# GOOGLE CHAT WEBHOOKS
# ============================================================================

GCHAT_SECURITY_WEBHOOK=
GCHAT_DEV_WEBHOOK=

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================

BACKUP_RETENTION_DAYS=90
BACKUP_SCHEDULE="0 2 * * *"

# ============================================================================
# MONITORING CONFIGURATION
# ============================================================================

PROMETHEUS_ENABLED=true
GRAFANA_ENABLED=true
EOF

    chmod 600 .env.gitea
    log_success ".env.gitea created successfully"

    # Display important tokens
    echo ""
    log_info "Important tokens (save these securely):"
    echo "  Metrics Token: ${GITEA_METRICS_TOKEN}"
    echo "  N8N API Key: ${N8N_API_KEY}"
    echo "  Atlantis Webhook Secret: ${ATLANTIS_WEBHOOK_SECRET}"
    echo ""
}

create_directories() {
    log_info "Creating necessary directories..."

    cd "$PROJECT_DIR"

    mkdir -p backups/postgres-gitea
    mkdir -p logs/gitea
    mkdir -p config

    log_success "Directories created"
}

deploy_gitea() {
    log_info "Deploying Gitea containers..."

    cd "$PROJECT_DIR"

    # Pull latest images
    log_info "Pulling Docker images..."
    docker-compose -f docker-compose-gitea.yml pull

    # Start services
    log_info "Starting services..."
    docker-compose -f docker-compose-gitea.yml up -d

    log_success "Gitea containers deployed"
}

wait_for_gitea() {
    log_info "Waiting for Gitea to start (this may take 60-90 seconds)..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s -f http://localhost:3000/api/healthz > /dev/null 2>&1; then
            log_success "Gitea is ready!"
            return 0
        fi

        echo -n "."
        sleep 3
        attempt=$((attempt + 1))
    done

    log_error "Gitea failed to start within expected time"
    return 1
}

configure_runner() {
    log_info "Configuring Gitea Actions Runner..."

    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  MANUAL STEP REQUIRED: Configure Actions Runner     ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "1. Open Gitea: http://localhost:3000"
    echo "2. Login as: ${GITEA_ADMIN_USER}"
    echo "3. Go to: Admin Panel → Actions → Runners"
    echo "4. Click 'Create Registration Token'"
    echo "5. Copy the token"
    echo ""

    read -p "Paste the runner registration token here: " RUNNER_TOKEN

    if [ -n "$RUNNER_TOKEN" ]; then
        # Update .env.gitea
        sed -i "s/GITEA_RUNNER_TOKEN=.*/GITEA_RUNNER_TOKEN=${RUNNER_TOKEN}/" .env.gitea

        # Restart runner with token
        docker-compose -f docker-compose-gitea.yml restart gitea-runner

        log_success "Runner configured successfully"
    else
        log_warning "Runner token not provided. You can configure it later."
    fi
}

display_access_info() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Gitea Deployment Successful!                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Access Information:${NC}"
    echo "  Web UI:       http://localhost:3000"
    echo "  SSH:          ssh://git@localhost:2222"
    echo "  Admin User:   ${GITEA_ADMIN_USER}"
    echo ""
    echo -e "${BLUE}Running Containers:${NC}"
    docker-compose -f docker-compose-gitea.yml ps
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Configure Actions Runner (if not done)"
    echo "  2. Deploy other platform components:"
    echo "     make deploy-phase1a"
    echo "     make deploy-n8n"
    echo "     make monitoring-deploy"
    echo "     make atlantis-deploy"
    echo "  3. Configure webhooks for integrations"
    echo "  4. Review docs/GITEA_CONTAINER_GUIDE.md"
    echo ""
    echo -e "${YELLOW}Important Files:${NC}"
    echo "  Configuration: .env.gitea"
    echo "  Compose File:  docker-compose-gitea.yml"
    echo "  Runner Config: config/runner-config.yaml"
    echo "  Logs:          logs/gitea/"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    log_info "Starting Gitea container deployment..."
    echo ""

    # Check dependencies
    check_dependencies

    # Generate secrets
    generate_secrets

    # Create .env file
    create_env_file

    # Create directories
    create_directories

    # Deploy containers
    deploy_gitea

    # Wait for Gitea
    if wait_for_gitea; then
        # Configure runner
        configure_runner

        # Display access info
        display_access_info
    else
        log_error "Deployment may have issues. Check logs:"
        echo "  docker-compose -f docker-compose-gitea.yml logs gitea"
        exit 1
    fi

    log_success "Gitea container deployment complete!"
}

# Run main function
main "$@"
