#!/bin/bash

# n8n Automated Deployment Script
# This script deploys n8n with PostgreSQL and configures the DevSecOps workflow

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_TEMPLATE="$PROJECT_ROOT/.env.n8n.template"

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    print_info "Checking system requirements..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi

    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker service."
        exit 1
    fi

    print_info "All requirements met."
}

generate_passwords() {
    print_info "Generating secure passwords..."

    # Generate random passwords if not already set
    if [ -z "${POSTGRES_PASSWORD}" ]; then
        export POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi

    if [ -z "${N8N_BASIC_AUTH_PASSWORD}" ]; then
        export N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi

    if [ -z "${N8N_ENCRYPTION_KEY}" ]; then
        export N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
    fi

    if [ -z "${REDIS_PASSWORD}" ]; then
        export REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi

    if [ -z "${WEBHOOK_API_KEY}" ]; then
        export WEBHOOK_API_KEY=$(openssl rand -hex 32)
    fi
}

setup_environment() {
    print_info "Setting up environment configuration..."

    # Check if .env file exists
    if [ -f "$ENV_FILE" ]; then
        print_warn ".env file already exists. Loading existing configuration..."
        source "$ENV_FILE"
    else
        print_info "Creating .env file from template..."
        cp "$ENV_TEMPLATE" "$ENV_FILE"

        # Generate and set passwords
        generate_passwords

        # Update .env file with generated passwords
        sed -i "s/generate_secure_password_here/$POSTGRES_PASSWORD/" "$ENV_FILE"
        sed -i "s/generate_secure_admin_password/$N8N_BASIC_AUTH_PASSWORD/" "$ENV_FILE"
        sed -i "s/generate_32_char_random_string_here/$N8N_ENCRYPTION_KEY/" "$ENV_FILE"
        sed -i "s/generate_secure_redis_password/$REDIS_PASSWORD/" "$ENV_FILE"
        sed -i "s/generate_secure_api_key_here/$WEBHOOK_API_KEY/" "$ENV_FILE"

        print_info "Generated passwords saved to .env file"
    fi
}

create_directories() {
    print_info "Creating necessary directories..."

    mkdir -p "$PROJECT_ROOT/n8n/workflows"
    mkdir -p "$PROJECT_ROOT/n8n/custom"
    mkdir -p "$PROJECT_ROOT/config"
    mkdir -p "$PROJECT_ROOT/scripts"
    mkdir -p "$PROJECT_ROOT/tests/sample-events"
    mkdir -p "$PROJECT_ROOT/docs"

    print_info "Directory structure created."
}

setup_database() {
    print_info "Setting up database initialization script..."

    cat > "$PROJECT_ROOT/config/init-db.sql" << 'EOF'
-- n8n Database Initialization
-- Create necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create audit table for compliance
CREATE TABLE IF NOT EXISTS workflow_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_id VARCHAR(255),
    workflow_name VARCHAR(255),
    execution_id VARCHAR(255),
    event_type VARCHAR(100),
    event_data JSONB,
    user_id VARCHAR(255),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hash VARCHAR(64) GENERATED ALWAYS AS (
        encode(digest(event_data::text, 'sha256'), 'hex')
    ) STORED
);

-- Create index for faster queries
CREATE INDEX idx_workflow_audit_timestamp ON workflow_audit(timestamp DESC);
CREATE INDEX idx_workflow_audit_workflow_id ON workflow_audit(workflow_id);
CREATE INDEX idx_workflow_audit_event_type ON workflow_audit(event_type);

-- Create compliance evidence table
CREATE TABLE IF NOT EXISTS compliance_evidence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id VARCHAR(255) UNIQUE,
    event_type VARCHAR(100),
    severity VARCHAR(50),
    evidence_data JSONB,
    storage_location VARCHAR(500),
    hash VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    retention_until TIMESTAMP
);

-- Create index for compliance queries
CREATE INDEX idx_compliance_evidence_event_type ON compliance_evidence(event_type);
CREATE INDEX idx_compliance_evidence_severity ON compliance_evidence(severity);
CREATE INDEX idx_compliance_evidence_created_at ON compliance_evidence(created_at DESC);
EOF

    print_info "Database initialization script created."
}

setup_hooks() {
    print_info "Setting up n8n hooks for audit logging..."

    cat > "$PROJECT_ROOT/config/hooks.js" << 'EOF'
// n8n External Hooks for Audit Logging
module.exports = {
  workflow: {
    // Log workflow activations
    activate: async function(workflowData) {
      console.log(`[AUDIT] Workflow activated: ${workflowData.name} (${workflowData.id})`);
    },

    // Log workflow deactivations
    deactivate: async function(workflowData) {
      console.log(`[AUDIT] Workflow deactivated: ${workflowData.name} (${workflowData.id})`);
    },

    // Log workflow updates
    update: async function(workflowData) {
      console.log(`[AUDIT] Workflow updated: ${workflowData.name} (${workflowData.id})`);
    },

    // Log workflow deletions
    delete: async function(workflowId) {
      console.log(`[AUDIT] Workflow deleted: ${workflowId}`);
    }
  },

  // Log workflow executions
  workflowExecute: {
    before: async function(workflow, mode) {
      console.log(`[AUDIT] Workflow execution started: ${workflow.name} (${workflow.id}) - Mode: ${mode}`);
    },

    after: async function(workflow, mode, runData) {
      const status = runData.finished ? 'completed' : 'failed';
      console.log(`[AUDIT] Workflow execution ${status}: ${workflow.name} (${workflow.id}) - Mode: ${mode}`);
    }
  },

  // Log credential operations for security
  credentials: {
    create: async function(credentialData) {
      console.log(`[AUDIT] Credential created: ${credentialData.name} (Type: ${credentialData.type})`);
    },

    update: async function(credentialData) {
      console.log(`[AUDIT] Credential updated: ${credentialData.name} (Type: ${credentialData.type})`);
    },

    delete: async function(credentialId) {
      console.log(`[AUDIT] Credential deleted: ${credentialId}`);
    }
  }
};
EOF

    print_info "Audit hooks configured."
}

deploy_stack() {
    print_info "Deploying n8n stack with Docker Compose..."

    cd "$PROJECT_ROOT"

    # Use appropriate docker compose command
    if command -v docker-compose &> /dev/null; then
        docker-compose -f docker-compose-n8n.yml up -d
    else
        docker compose -f docker-compose-n8n.yml up -d
    fi

    print_info "Waiting for services to be healthy..."
    sleep 10

    # Wait for n8n to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz | grep -q "200"; then
            print_info "n8n is ready!"
            break
        fi
        attempt=$((attempt + 1))
        print_info "Waiting for n8n to start... (attempt $attempt/$max_attempts)"
        sleep 5
    done

    if [ $attempt -eq $max_attempts ]; then
        print_error "n8n failed to start. Check logs with: docker-compose -f docker-compose-n8n.yml logs"
        exit 1
    fi
}

import_workflow() {
    print_info "Preparing to import DevSecOps workflow..."

    # Wait a bit more for n8n to fully initialize
    sleep 5

    # Get n8n credentials from environment
    N8N_USER="${N8N_BASIC_AUTH_USER:-admin}"
    N8N_PASS="${N8N_BASIC_AUTH_PASSWORD}"

    if [ -z "$N8N_PASS" ]; then
        # Try to get from .env file
        N8N_PASS=$(grep "N8N_BASIC_AUTH_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    fi

    print_info "Importing workflow via API..."

    # Import workflow using the n8n API
    WORKFLOW_FILE="$PROJECT_ROOT/n8n/workflows/devsecops-security-automation.json"

    if [ -f "$WORKFLOW_FILE" ]; then
        # First, get the API endpoint status
        API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "${N8N_USER}:${N8N_PASS}" \
            "http://localhost:5678/api/v1/workflows")

        if [ "$API_STATUS" = "200" ]; then
            print_info "API is accessible, importing workflow..."

            # Import the workflow
            IMPORT_RESPONSE=$(curl -s -X POST \
                -u "${N8N_USER}:${N8N_PASS}" \
                -H "Content-Type: application/json" \
                -d @"$WORKFLOW_FILE" \
                "http://localhost:5678/api/v1/workflows")

            if echo "$IMPORT_RESPONSE" | grep -q '"id"'; then
                WORKFLOW_ID=$(echo "$IMPORT_RESPONSE" | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)
                print_info "Workflow imported successfully with ID: $WORKFLOW_ID"

                # Activate the workflow
                curl -s -X PATCH \
                    -u "${N8N_USER}:${N8N_PASS}" \
                    -H "Content-Type: application/json" \
                    -d '{"active": true}' \
                    "http://localhost:5678/api/v1/workflows/$WORKFLOW_ID" > /dev/null

                print_info "Workflow activated!"
            else
                print_warn "Workflow import returned unexpected response. Manual import may be needed."
                print_warn "Response: $IMPORT_RESPONSE"
            fi
        else
            print_warn "n8n API not accessible (Status: $API_STATUS). You'll need to import the workflow manually."
            print_warn "Workflow file location: $WORKFLOW_FILE"
        fi
    else
        print_error "Workflow file not found at: $WORKFLOW_FILE"
    fi
}

print_summary() {
    print_info "================================="
    print_info "n8n Deployment Complete!"
    print_info "================================="

    # Get credentials
    N8N_USER="${N8N_BASIC_AUTH_USER:-admin}"
    N8N_PASS=$(grep "N8N_BASIC_AUTH_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    WEBHOOK_KEY=$(grep "WEBHOOK_API_KEY=" "$ENV_FILE" | cut -d'=' -f2)

    echo ""
    echo "Access Details:"
    echo "---------------"
    echo "n8n URL: http://localhost:5678"
    echo "Username: $N8N_USER"
    echo "Password: $N8N_PASS"
    echo ""
    echo "Webhook URL: https://n8n.example.com/webhook/security-events"
    echo "Webhook API Key: $WEBHOOK_KEY"
    echo ""
    echo "Next Steps:"
    echo "-----------"
    echo "1. Configure your domain in .env (N8N_HOST)"
    echo "2. Update Caddy configuration with your domain"
    echo "3. Configure credentials in n8n UI:"
    echo "   - Google Chat webhooks"
    echo "   - Gitea API token"
    echo "   - GCP service account"
    echo "   - Email SMTP settings"
    echo "4. Test webhooks using: ./scripts/test-n8n-workflows.sh"
    echo ""
    echo "Useful Commands:"
    echo "----------------"
    echo "View logs: docker-compose -f docker-compose-n8n.yml logs -f"
    echo "Stop services: docker-compose -f docker-compose-n8n.yml down"
    echo "Restart services: docker-compose -f docker-compose-n8n.yml restart"
    echo ""
    print_info "Setup complete!"
}

# Main execution
main() {
    print_info "Starting n8n deployment..."

    check_requirements
    setup_environment
    create_directories
    setup_database
    setup_hooks
    deploy_stack
    import_workflow
    print_summary
}

# Run main function
main "$@"