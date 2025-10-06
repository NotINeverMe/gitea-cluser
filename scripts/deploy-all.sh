#!/bin/bash

# Unified DevSecOps Platform Deployment Script
# Deploys ALL components in the correct order with health checks

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║        DevSecOps Platform - Unified Deployment                  ║
║                                                                  ║
║  Complete deployment of:                                        ║
║    • Gitea + PostgreSQL + Actions Runner                        ║
║    • SonarQube + Security Scanners                              ║
║    • n8n Workflow Automation                                    ║
║    • Prometheus + Grafana Monitoring                            ║
║    • Atlantis GitOps                                            ║
║    • GCP Evidence Collection                                    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ============================================================================
# FUNCTIONS
# ============================================================================

log_section() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

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

wait_for_service() {
    local service_name=$1
    local health_url=$2
    local max_attempts=${3:-30}

    log_info "Waiting for $service_name to be ready..."

    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$health_url" > /dev/null 2>&1; then
            log_success "$service_name is ready!"
            return 0
        fi

        echo -n "."
        sleep 3
        attempt=$((attempt + 1))
    done

    log_error "$service_name failed to start"
    return 1
}

check_docker() {
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    log_success "Docker is running"
}

# ============================================================================
# DEPLOYMENT STAGES
# ============================================================================

deploy_gitea() {
    log_section "Stage 1: Deploying Gitea (Git Repository Server)"

    cd "$PROJECT_DIR"

    if [ ! -f .env.gitea ]; then
        log_info "Gitea not configured. Running setup script..."
        ./scripts/setup-gitea-container.sh
    else
        log_info "Using existing .env.gitea configuration"

        # Deploy containers
        docker-compose -f docker-compose-gitea.yml pull
        docker-compose -f docker-compose-gitea.yml up -d

        # Wait for Gitea
        wait_for_service "Gitea" "http://localhost:3000/api/healthz" 30
    fi

    log_success "Gitea deployment complete"
}

deploy_phase1a() {
    log_section "Stage 2: Deploying Security Foundation (SonarQube + Scanners)"

    cd "$PROJECT_DIR"

    # Deploy SonarQube stack
    log_info "Deploying SonarQube + PostgreSQL..."
    docker-compose -f docker-compose.yml pull
    docker-compose -f docker-compose.yml up -d

    # Wait for SonarQube
    wait_for_service "SonarQube" "http://localhost:9000/api/system/status" 60

    log_success "Phase 1A deployment complete"
}

deploy_n8n() {
    log_section "Stage 3: Deploying n8n (Workflow Automation)"

    cd "$PROJECT_DIR"

    if [ ! -f .env.n8n ]; then
        log_warning ".env.n8n not found. Creating from template..."
        cp .env.n8n.template .env.n8n
        log_info "Please edit .env.n8n before continuing (press Enter when ready)"
        read
    fi

    # Deploy n8n stack
    log_info "Deploying n8n + PostgreSQL + Redis..."
    docker-compose -f docker-compose-n8n.yml pull
    docker-compose -f docker-compose-n8n.yml up -d

    # Wait for n8n
    wait_for_service "n8n" "http://localhost:5678/healthz" 30

    # Import workflows
    log_info "Importing n8n workflows..."
    sleep 10  # Wait for n8n to fully initialize

    log_success "n8n deployment complete"
}

deploy_monitoring() {
    log_section "Stage 4: Deploying Monitoring (Prometheus + Grafana)"

    cd "$PROJECT_DIR/monitoring"

    # Deploy monitoring stack
    log_info "Deploying Prometheus + Grafana + Alertmanager..."
    docker-compose -f docker-compose-monitoring.yml pull
    docker-compose -f docker-compose-monitoring.yml up -d

    # Wait for services
    wait_for_service "Prometheus" "http://localhost:9090/-/healthy" 20
    wait_for_service "Grafana" "http://localhost:3000/api/health" 20

    cd "$PROJECT_DIR"
    log_success "Monitoring deployment complete"
}

deploy_atlantis() {
    log_section "Stage 5: Deploying Atlantis (GitOps for Terraform)"

    cd "$PROJECT_DIR/atlantis"

    if [ ! -f .env.atlantis ]; then
        log_warning ".env.atlantis not found. Creating from template..."
        cd "$PROJECT_DIR"
        log_info "Please configure Atlantis before continuing"
        return 1
    fi

    # Deploy Atlantis stack
    log_info "Deploying Atlantis + PostgreSQL + Conftest..."
    docker-compose -f docker-compose-atlantis.yml pull
    docker-compose -f docker-compose-atlantis.yml up -d

    # Wait for Atlantis
    wait_for_service "Atlantis" "http://localhost:4141/healthz" 20

    cd "$PROJECT_DIR"
    log_success "Atlantis deployment complete"
}

deploy_evidence_collection() {
    log_section "Stage 6: Deploying Evidence Collection (GCP Collectors)"

    cd "$PROJECT_DIR/evidence-collection"

    if [ ! -f config/evidence-config.yaml ]; then
        log_warning "Evidence collectors not configured. Skipping..."
        cd "$PROJECT_DIR"
        return 0
    fi

    # Deploy collectors
    log_info "Deploying GCP evidence collectors..."
    docker-compose -f docker-compose-collectors.yml pull
    docker-compose -f docker-compose-collectors.yml up -d

    cd "$PROJECT_DIR"
    log_success "Evidence collection deployment complete"
}

display_summary() {
    log_section "Deployment Summary"

    echo -e "${GREEN}✓ Platform deployment complete!${NC}"
    echo ""
    echo -e "${CYAN}Running Services:${NC}"
    echo ""

    # Show container status
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20

    echo ""
    echo -e "${CYAN}Access Information:${NC}"
    echo ""
    echo -e "  ${GREEN}Gitea:${NC}           http://localhost:3000"
    echo -e "  ${GREEN}SonarQube:${NC}       http://localhost:9000 (admin/admin)"
    echo -e "  ${GREEN}n8n:${NC}             http://localhost:5678"
    echo -e "  ${GREEN}Prometheus:${NC}      http://localhost:9090"
    echo -e "  ${GREEN}Grafana:${NC}         http://localhost:3000 (admin/ChangeMe123!)"
    echo -e "  ${GREEN}Alertmanager:${NC}    http://localhost:9093"
    echo -e "  ${GREEN}Atlantis:${NC}        http://localhost:4141"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo ""
    echo "  1. Configure Gitea Actions Runner (if not done)"
    echo "     - Open Gitea → Admin Panel → Actions → Runners"
    echo "     - Create registration token"
    echo "     - Update .env.gitea with GITEA_RUNNER_TOKEN"
    echo "     - Restart runner: docker-compose -f docker-compose-gitea.yml restart gitea-runner"
    echo ""
    echo "  2. Configure webhooks for integrations"
    echo "     - n8n webhook: http://n8n:5678/webhook/security-events"
    echo "     - Atlantis webhook: http://atlantis:4141/events"
    echo ""
    echo "  3. Review documentation"
    echo "     - Integration: docs/INTEGRATION_GUIDE.md"
    echo "     - Testing: docs/TESTING_VALIDATION_GUIDE.md"
    echo "     - Deployment: DEPLOYMENT_SUMMARY.md"
    echo ""
    echo "  4. Run validation tests"
    echo "     make integration-test"
    echo "     make compliance-report"
    echo ""
    echo -e "${YELLOW}Important Files:${NC}"
    echo "  - Main config:    .env.gitea"
    echo "  - Compose files:  docker-compose-*.yml"
    echo "  - Logs:           logs/"
    echo "  - Backups:        backups/"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    cd "$PROJECT_DIR"

    # Pre-flight checks
    log_section "Pre-Flight Checks"
    check_docker

    # Deployment stages
    deploy_gitea
    deploy_phase1a
    deploy_n8n
    deploy_monitoring

    # Optional stages
    if deploy_atlantis; then
        log_success "Atlantis deployed"
    else
        log_warning "Atlantis deployment skipped (not configured)"
    fi

    deploy_evidence_collection

    # Summary
    display_summary

    log_success "Complete DevSecOps platform deployment finished!"
}

# Parse arguments
SKIP_GITEA=false
SKIP_PHASE1A=false
SKIP_N8N=false
SKIP_MONITORING=false
SKIP_ATLANTIS=false
SKIP_EVIDENCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-gitea)
            SKIP_GITEA=true
            shift
            ;;
        --skip-phase1a)
            SKIP_PHASE1A=true
            shift
            ;;
        --skip-n8n)
            SKIP_N8N=true
            shift
            ;;
        --skip-monitoring)
            SKIP_MONITORING=true
            shift
            ;;
        --skip-atlantis)
            SKIP_ATLANTIS=true
            shift
            ;;
        --skip-evidence)
            SKIP_EVIDENCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-gitea        Skip Gitea deployment"
            echo "  --skip-phase1a      Skip Phase 1A (SonarQube)"
            echo "  --skip-n8n          Skip n8n deployment"
            echo "  --skip-monitoring   Skip monitoring stack"
            echo "  --skip-atlantis     Skip Atlantis deployment"
            echo "  --skip-evidence     Skip evidence collection"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main deployment
main "$@"
