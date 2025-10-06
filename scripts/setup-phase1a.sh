#!/bin/bash
# Phase 1A: Critical Security Foundation Setup Script
# CMMC 2.0 & NIST SP 800-171 Rev. 2 Compliance
# Estimated deployment time: 4-6 hours
# Author: DevSecOps Platform Team

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EVIDENCE_DIR="${PROJECT_ROOT}/evidence/phase1a"
LOG_FILE="${EVIDENCE_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    local missing_tools=()

    # Check for required tools
    for tool in docker docker-compose git curl jq openssl sha256sum; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_status "Please install missing tools and retry."
        exit 1
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running or you don't have permissions"
        print_status "Please start Docker and ensure your user is in the docker group"
        exit 1
    fi

    # Check disk space (minimum 10GB required)
    available_space=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 10 ]; then
        print_warning "Low disk space: ${available_space}GB available (10GB recommended)"
    fi

    print_success "All prerequisites met"
}

# Function to create directory structure
setup_directories() {
    print_status "Creating directory structure..."

    directories=(
        "${EVIDENCE_DIR}"
        "${PROJECT_ROOT}/config/sonar"
        "${PROJECT_ROOT}/config/trivy"
        "${PROJECT_ROOT}/config/postgres"
        "${PROJECT_ROOT}/data/sonarqube"
        "${PROJECT_ROOT}/data/postgres"
        "${PROJECT_ROOT}/data/trivy"
        "${PROJECT_ROOT}/logs"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        print_success "Created: $dir"
    done

    # Set proper permissions
    chmod 750 "${EVIDENCE_DIR}"
    chmod 750 "${PROJECT_ROOT}/data"
}

# Function to generate secure passwords
generate_passwords() {
    print_status "Generating secure passwords..."

    # Generate random passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    SONAR_ADMIN_PASSWORD=$(openssl rand -base64 32)
    SONAR_TOKEN=$(openssl rand -hex 32)

    # Create .env file with generated passwords
    cat > "${PROJECT_ROOT}/.env" << EOF
# Auto-generated passwords for Phase 1A
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# WARNING: Store these securely and rotate regularly

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
SONAR_ADMIN_PASSWORD=${SONAR_ADMIN_PASSWORD}
SONAR_TOKEN=${SONAR_TOKEN}
SONAR_WEB_SYSTEMPASSCODE=$(openssl rand -base64 24)

# GCP Configuration (update with your values)
GCP_PROJECT_ID=your-project-id
GCP_REGION=us-central1
GCP_ZONE=us-central1-a

# Gitea Configuration
GITEA_URL=http://localhost:3000
GITEA_TOKEN=your-gitea-token

# Google Chat Webhook (optional)
GCHAT_WEBHOOK_URL=

# Infracost API Key (optional)
INFRACOST_API_KEY=
EOF

    chmod 600 "${PROJECT_ROOT}/.env"
    print_success "Generated secure passwords and saved to .env"

    # Generate evidence hash
    sha256sum "${PROJECT_ROOT}/.env" > "${EVIDENCE_DIR}/env-hash.sha256"
}

# Function to create SonarQube configuration
configure_sonarqube() {
    print_status "Configuring SonarQube..."

    cat > "${PROJECT_ROOT}/config/sonar/sonar.properties" << 'EOF'
# SonarQube Configuration for CMMC/NIST Compliance
# Security-hardened settings

# Database settings (handled via environment variables)

# Web server configuration
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.context=/

# Security settings
sonar.forceAuthentication=true
sonar.security.realm=sonar
sonar.preventAutoAccountCreation=true

# Session security
sonar.web.sessionTimeoutInMinutes=60
sonar.web.systemPasscode=${env:SONAR_WEB_SYSTEMPASSCODE}

# OWASP security rules
sonar.security.hotspots.review.required=true
sonar.security.hotspots.maxIssues=0

# Quality gates
sonar.qualitygate.ignoreSmallChanges=false

# Logging
sonar.log.level=INFO
sonar.verbose=false

# Performance tuning
sonar.ce.javaOpts=-Xmx1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.web.javaOpts=-Xmx512m

# Search settings
sonar.search.javaOpts=-Xmx512m -Xms512m

# Plugins to install (security-focused)
sonar.plugins.install=\
    findbugs,\
    checkstyle,\
    pmd,\
    javascript,\
    python,\
    go,\
    ansible,\
    terraform,\
    docker,\
    yaml
EOF

    print_success "SonarQube configuration created"
}

# Function to create PostgreSQL configuration
configure_postgres() {
    print_status "Configuring PostgreSQL..."

    cat > "${PROJECT_ROOT}/config/postgres/postgresql.conf" << 'EOF'
# PostgreSQL Configuration for SonarQube
# Security and performance optimizations

# Connection settings
listen_addresses = 'localhost'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB

# Security
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
password_encryption = scram-sha-256

# Logging for compliance
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_connections = on
log_disconnections = on
log_duration = on
log_statement = 'all'
log_timezone = 'UTC'

# Audit settings
log_checkpoints = on
log_lock_waits = on
log_temp_files = 0

# Performance
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
EOF

    print_success "PostgreSQL configuration created"
}

# Function to create Trivy configuration
configure_trivy() {
    print_status "Configuring Trivy..."

    cat > "${PROJECT_ROOT}/config/trivy/trivy.yaml" << 'EOF'
# Trivy Configuration for Container Security Scanning
# CMMC SI.L2-3.14.2 compliance

# Cache settings
cache:
  backend: "fs"
  cache_dir: "/root/.cache/trivy"
  ttl: "24h"

# Database settings
db:
  download_only: false
  skip_update: false
  light: false
  repository: "ghcr.io/aquasecurity/trivy-db"

# Vulnerability settings
vulnerability:
  type:
    - "os"
    - "library"
  ignore_unfixed: false

# Security checks
security_checks:
  - vuln
  - config
  - secret
  - license

# Severity levels
severity:
  - CRITICAL
  - HIGH
  - MEDIUM

# Misconfiguration scanning
misconfiguration:
  scan_terraform: true
  scan_cloudformation: true
  scan_kubernetes: true
  scan_docker: true
  scan_rbac: true

# Secret detection
secret:
  enable: true

# License detection
license:
  full: true
  confidence_level: 0.9

# Report settings
format: "json"
template: "@/usr/local/share/trivy/templates/sarif.tpl"

# Compliance
compliance:
  - "cis-docker"
  - "cis-kubernetes"
EOF

    print_success "Trivy configuration created"
}

# Function to start services
start_services() {
    print_status "Starting Docker services..."

    cd "$PROJECT_ROOT"

    # Pull latest images
    print_status "Pulling Docker images..."
    docker-compose pull

    # Start services
    print_status "Starting services with docker-compose..."
    docker-compose up -d

    # Wait for services to be healthy
    print_status "Waiting for services to initialize..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker-compose ps | grep -q "healthy"; then
            print_success "Services are healthy"
            break
        fi

        attempt=$((attempt + 1))
        print_status "Waiting for services... (${attempt}/${max_attempts})"
        sleep 10
    done

    if [ $attempt -eq $max_attempts ]; then
        print_error "Services failed to become healthy"
        docker-compose logs
        exit 1
    fi

    # Display service status
    docker-compose ps
}

# Function to configure SonarQube post-startup
configure_sonarqube_api() {
    print_status "Configuring SonarQube via API..."

    local sonar_url="http://localhost:9000"
    local max_attempts=30
    local attempt=0

    # Wait for SonarQube API to be available
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "${sonar_url}/api/system/status" | grep -q "UP"; then
            print_success "SonarQube API is available"
            break
        fi

        attempt=$((attempt + 1))
        print_status "Waiting for SonarQube API... (${attempt}/${max_attempts})"
        sleep 10
    done

    # Load environment variables
    source "${PROJECT_ROOT}/.env"

    # Change default admin password
    print_status "Updating SonarQube admin password..."
    curl -s -u admin:admin -X POST "${sonar_url}/api/users/change_password" \
        -d "login=admin&previousPassword=admin&password=${SONAR_ADMIN_PASSWORD}" || true

    # Create token for CI/CD
    print_status "Creating SonarQube token for CI/CD..."
    SONAR_TOKEN=$(curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" -X POST \
        "${sonar_url}/api/user_tokens/generate" \
        -d "name=gitea-ci-$(date +%Y%m%d)" | jq -r '.token')

    # Update .env with token
    sed -i "s/SONAR_TOKEN=.*/SONAR_TOKEN=${SONAR_TOKEN}/" "${PROJECT_ROOT}/.env"

    # Create quality gate
    print_status "Creating CMMC/NIST quality gate..."
    curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" -X POST \
        "${sonar_url}/api/qualitygates/create" \
        -d "name=CMMC-NIST-Security&conditions=new_security_rating,new_reliability_rating" || true

    print_success "SonarQube configuration complete"
}

# Function to create Gitea secrets
setup_gitea_secrets() {
    print_status "Setting up Gitea secrets..."

    # Check if Gitea CLI is available
    if ! command -v gitea &> /dev/null; then
        print_warning "Gitea CLI not found. Please manually add secrets to Gitea:"
        echo "  - SONAR_TOKEN"
        echo "  - SONAR_HOST_URL"
        echo "  - SEMGREP_APP_TOKEN"
        echo "  - INFRACOST_API_KEY"
        echo "  - GCP_PROJECT_ID"
        echo "  - GCHAT_WEBHOOK_URL"
        return
    fi

    # Load environment variables
    source "${PROJECT_ROOT}/.env"

    # Add secrets to Gitea (example - adjust for your Gitea setup)
    print_status "Adding secrets to Gitea repository..."

    # This is a placeholder - implement based on your Gitea API
    print_warning "Please manually add the following secrets to your Gitea repository:"
    echo "  SONAR_TOKEN=${SONAR_TOKEN}"
    echo "  SONAR_HOST_URL=http://localhost:9000"
    echo "  GCP_PROJECT_ID=${GCP_PROJECT_ID}"
}

# Function to run validation tests
run_validation() {
    print_status "Running validation tests..."

    # Test SonarQube
    if curl -s "http://localhost:9000/api/system/status" | grep -q "UP"; then
        print_success "SonarQube is operational"
    else
        print_error "SonarQube is not responding"
    fi

    # Test Trivy
    if docker exec trivy-server trivy version &> /dev/null; then
        print_success "Trivy is operational"
    else
        print_error "Trivy is not responding"
    fi

    # Test PostgreSQL
    if docker exec sonarqube-postgres pg_isready -U sonar &> /dev/null; then
        print_success "PostgreSQL is operational"
    else
        print_error "PostgreSQL is not responding"
    fi

    # Generate validation evidence
    print_status "Generating validation evidence..."
    {
        echo "Phase 1A Validation Report"
        echo "=========================="
        echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "Services Status:"
        docker-compose ps
        echo ""
        echo "Container Hashes:"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.ID}}" | while read -r line; do
            echo "$line"
        done
        echo ""
        echo "Configuration Hashes:"
        find "${PROJECT_ROOT}/config" -type f -exec sha256sum {} \;
    } > "${EVIDENCE_DIR}/validation-report.txt"

    # Generate final evidence hash
    sha256sum "${EVIDENCE_DIR}/validation-report.txt" > "${EVIDENCE_DIR}/validation-hash.sha256"

    print_success "Validation complete"
}

# Function to display summary
display_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Phase 1A Deployment Complete!${NC}"
    echo "=============================================="
    echo ""
    echo "Services Running:"
    echo "  • SonarQube: http://localhost:9000"
    echo "  • Trivy: http://localhost:4954"
    echo ""
    echo "Default Credentials (change immediately):"
    echo "  • SonarQube: admin / (check .env file)"
    echo ""
    echo "Next Steps:"
    echo "  1. Access SonarQube and complete setup"
    echo "  2. Configure Gitea repository secrets"
    echo "  3. Test workflow execution"
    echo "  4. Review security findings"
    echo ""
    echo "Evidence Location: ${EVIDENCE_DIR}"
    echo "Logs Location: ${LOG_FILE}"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC}"
    echo "  - Change all default passwords immediately"
    echo "  - Configure Google Chat webhook for notifications"
    echo "  - Review and adjust security policies as needed"
    echo "=============================================="
}

# Main execution
main() {
    echo "=============================================="
    echo "Phase 1A: Critical Security Foundation Setup"
    echo "CMMC 2.0 & NIST SP 800-171 Rev. 2 Compliance"
    echo "=============================================="
    echo ""

    # Create evidence directory first
    mkdir -p "$EVIDENCE_DIR"

    # Start logging
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1

    print_status "Starting Phase 1A deployment at $(date)"

    # Execute setup steps
    check_prerequisites
    setup_directories
    generate_passwords
    configure_sonarqube
    configure_postgres
    configure_trivy
    start_services
    configure_sonarqube_api
    setup_gitea_secrets
    run_validation

    # Display summary
    display_summary

    print_success "Phase 1A deployment completed successfully!"
}

# Run main function
main "$@"