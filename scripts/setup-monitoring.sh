#!/bin/bash

# Setup Monitoring Stack
# CMMC 2.0: AU.L2-3.3.1, SI.L2-3.14.4
# NIST SP 800-171: 3.3.1, 3.14.4
# NIST SP 800-53: AU-6, SI-4

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/monitoring-setup-$(date +%Y%m%d-%H%M%S).log"
EVIDENCE_DIR="../compliance/evidence/monitoring"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to generate evidence
generate_evidence() {
    local component=$1
    local status=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local evidence_file="$EVIDENCE_DIR/${component}-setup-${timestamp}.json"

    mkdir -p "$EVIDENCE_DIR"

    cat > "$evidence_file" <<EOF
{
  "component": "$component",
  "action": "setup",
  "status": "$status",
  "timestamp": "$timestamp",
  "compliance": {
    "cmmc": ["AU.L2-3.3.1", "SI.L2-3.14.4"],
    "nist_171": ["3.3.1", "3.14.4"],
    "nist_53": ["AU-6", "SI-4"]
  },
  "hash": "$(sha256sum $LOG_FILE | cut -d' ' -f1)"
}
EOF

    log "Evidence generated: $evidence_file"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed"
    fi

    # Check required files
    local required_files=(
        "monitoring/docker-compose-monitoring.yml"
        "monitoring/prometheus/prometheus.yml"
        "monitoring/alertmanager/alertmanager.yml"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "Required file not found: $file"
        fi
    done

    log "Prerequisites check passed"
}

# Create required directories
create_directories() {
    log "Creating required directories..."

    local dirs=(
        "monitoring/data/prometheus"
        "monitoring/data/grafana"
        "monitoring/data/alertmanager"
        "monitoring/data/postgres"
        "monitoring/grafana/dashboards/devsecops"
        "monitoring/grafana/dashboards/security"
        "monitoring/grafana/dashboards/compliance"
        "monitoring/grafana/dashboards/infrastructure"
        "monitoring/grafana/dashboards/cicd"
        "monitoring/grafana/dashboards/cost"
        "monitoring/exporters/scan-results"
        "compliance/evidence/monitoring"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
        log "Created directory: $dir"
    done
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."

    if [ ! -f "monitoring/.env" ]; then
        cat > monitoring/.env <<'EOF'
# Grafana Configuration
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=ChangeMe123!
GRAFANA_DB_PASSWORD=ChangeMe123!
GRAFANA_SECRET_KEY=SW2YcwTIb9zOOi1QaMcukeTQoD4wMWm1
GRAFANA_DOMAIN=monitoring.example.com

# OAuth2 Configuration (Google)
OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
OAUTH_CLIENT_SECRET=your-client-secret
ALLOWED_DOMAINS=example.com

# Google Chat Webhooks
GCHAT_WEBHOOK_MONITORING=https://chat.googleapis.com/v1/spaces/SPACE_ID/messages?key=KEY&token=TOKEN
GCHAT_WEBHOOK_SECURITY=https://chat.googleapis.com/v1/spaces/SPACE_ID/messages?key=KEY&token=TOKEN
GCHAT_WEBHOOK_COMPLIANCE=https://chat.googleapis.com/v1/spaces/SPACE_ID/messages?key=KEY&token=TOKEN
GCHAT_WEBHOOK_CRITICAL=https://chat.googleapis.com/v1/spaces/SPACE_ID/messages?key=KEY&token=TOKEN
GCHAT_WEBHOOK_COST=https://chat.googleapis.com/v1/spaces/SPACE_ID/messages?key=KEY&token=TOKEN
GCHAT_WEBHOOK_DEVOPS=https://chat.googleapis.com/v1/spaces/SPACE_ID/messages?key=KEY&token=TOKEN

# Service URLs
SONARQUBE_URL=http://sonarqube:9000
SONARQUBE_TOKEN=your-sonarqube-token
TRIVY_API_URL=http://trivy:8080
GRYPE_API_URL=http://grype:8080

# AWS Credentials (for CloudWatch if needed)
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
EOF

        warning "Environment file created. Please update with actual values: monitoring/.env"
    else
        log "Environment file already exists"
    fi

    # Set proper permissions
    chmod 600 monitoring/.env
}

# Generate self-signed certificates (for testing)
generate_certificates() {
    log "Generating self-signed certificates..."

    local cert_dir="monitoring/certs"
    mkdir -p "$cert_dir"

    if [ ! -f "$cert_dir/server.crt" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$cert_dir/server.key" \
            -out "$cert_dir/server.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/OU=DevSecOps/CN=*.example.com" \
            2>/dev/null

        chmod 400 "$cert_dir/server.key"
        chmod 444 "$cert_dir/server.crt"

        log "Self-signed certificates generated"
    else
        log "Certificates already exist"
    fi
}

# Build custom exporters
build_exporters() {
    log "Building custom exporters..."

    cd monitoring/exporters

    # Build SonarQube exporter
    log "Building SonarQube exporter..."
    docker build -f Dockerfile.sonarqube -t sonarqube-exporter:latest .

    # Build Security Scan exporter
    log "Building Security Scan exporter..."
    docker build -f Dockerfile.security -t security-scan-exporter:latest .

    # Build Compliance exporter
    log "Building Compliance exporter..."
    docker build -f Dockerfile.compliance -t compliance-exporter:latest .

    cd ../..

    log "Custom exporters built successfully"
}

# Deploy monitoring stack
deploy_monitoring() {
    log "Deploying monitoring stack..."

    cd monitoring

    # Pull required images
    log "Pulling Docker images..."
    docker-compose -f docker-compose-monitoring.yml pull --ignore-pull-failures

    # Start services
    log "Starting monitoring services..."
    docker-compose -f docker-compose-monitoring.yml up -d

    # Wait for services to be ready
    log "Waiting for services to be ready..."
    sleep 30

    # Check service health
    local services=("prometheus" "grafana" "alertmanager")
    for service in "${services[@]}"; do
        if docker-compose -f docker-compose-monitoring.yml ps | grep -q "$service.*Up"; then
            log "$service is running"
        else
            warning "$service may not be running properly"
        fi
    done

    cd ..
}

# Configure Grafana dashboards
configure_dashboards() {
    log "Configuring Grafana dashboards..."

    # Wait for Grafana to be ready
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health | grep -q "200"; then
            log "Grafana is ready"
            break
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        warning "Grafana may not be fully ready"
    fi

    log "Dashboards will be automatically provisioned from monitoring/grafana/dashboards/"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."

    local endpoints=(
        "http://localhost:9090/-/healthy"  # Prometheus
        "http://localhost:3000/api/health"  # Grafana
        "http://localhost:9093/-/healthy"   # Alertmanager
        "http://localhost:9100/metrics"     # Node Exporter
        "http://localhost:9115/metrics"     # Blackbox Exporter
    )

    local all_healthy=true

    for endpoint in "${endpoints[@]}"; do
        if curl -s -o /dev/null -w "%{http_code}" "$endpoint" | grep -q "200"; then
            log "✓ Endpoint healthy: $endpoint"
        else
            warning "✗ Endpoint not responding: $endpoint"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        log "All endpoints are healthy"
        generate_evidence "monitoring-stack" "deployed"
    else
        warning "Some endpoints are not healthy"
        generate_evidence "monitoring-stack" "partial"
    fi
}

# Print access information
print_access_info() {
    log "=== Monitoring Stack Deployed Successfully ==="
    echo ""
    echo "Access URLs:"
    echo "  Grafana:       http://localhost:3000"
    echo "  Prometheus:    http://localhost:9090"
    echo "  Alertmanager:  http://localhost:9093"
    echo ""
    echo "Default Credentials:"
    echo "  Grafana:       admin / ChangeMe123!"
    echo ""
    echo "Next Steps:"
    echo "  1. Update monitoring/.env with actual values"
    echo "  2. Configure Google Chat webhooks for alerts"
    echo "  3. Set up OAuth2 for Grafana authentication"
    echo "  4. Import additional dashboards as needed"
    echo "  5. Review and customize alert rules"
    echo ""
    echo "Documentation:"
    echo "  - Deployment Guide: docs/MONITORING_DEPLOYMENT_GUIDE.md"
    echo "  - Dashboard Guide:  docs/GRAFANA_DASHBOARD_GUIDE.md"
    echo "  - Alerting Runbook: docs/ALERTING_RUNBOOK.md"
    echo ""
    echo "Evidence collected at: $EVIDENCE_DIR"
    echo "Log file: $LOG_FILE"
}

# Main execution
main() {
    log "Starting monitoring stack setup..."

    # Change to project root
    cd "$(dirname "$0")/.."

    check_prerequisites
    create_directories
    setup_environment
    generate_certificates
    build_exporters
    deploy_monitoring
    configure_dashboards
    verify_deployment
    print_access_info

    log "Monitoring stack setup completed"
}

# Run main function
main "$@"