#!/bin/bash

# n8n Credential Configuration Helper
# This script helps configure credentials in n8n via API

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

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

print_prompt() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    print_error ".env file not found. Please run setup-n8n.sh first."
    exit 1
fi

# n8n API Configuration
N8N_URL="${N8N_URL:-http://localhost:5678}"
N8N_USER="${N8N_BASIC_AUTH_USER:-admin}"
N8N_PASS="${N8N_BASIC_AUTH_PASSWORD}"

# Function to create credential via API
create_credential() {
    local cred_name=$1
    local cred_type=$2
    local cred_data=$3

    print_info "Creating credential: $cred_name"

    response=$(curl -s -X POST \
        -u "${N8N_USER}:${N8N_PASS}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$cred_name\",
            \"type\": \"$cred_type\",
            \"data\": $cred_data
        }" \
        "$N8N_URL/api/v1/credentials")

    if echo "$response" | grep -q '"id"'; then
        print_info "✓ Credential '$cred_name' created successfully"
        return 0
    else
        print_warn "Failed to create credential '$cred_name': $response"
        return 1
    fi
}

# Configure Google Chat Webhooks
configure_google_chat() {
    print_info "Configuring Google Chat webhooks..."

    print_prompt "Enter Google Chat Security Channel Webhook URL (or press Enter to skip):"
    read -r GCHAT_SECURITY_URL

    if [ -n "$GCHAT_SECURITY_URL" ]; then
        cred_data="{
            \"webhookUrl\": \"$GCHAT_SECURITY_URL\"
        }"
        create_credential "Google Chat - Security" "httpHeaderAuth" "$cred_data"

        # Update .env file
        sed -i "s|GCHAT_SECURITY_WEBHOOK=.*|GCHAT_SECURITY_WEBHOOK=$GCHAT_SECURITY_URL|" "$ENV_FILE"
    fi

    print_prompt "Enter Google Chat Dev Channel Webhook URL (or press Enter to skip):"
    read -r GCHAT_DEV_URL

    if [ -n "$GCHAT_DEV_URL" ]; then
        cred_data="{
            \"webhookUrl\": \"$GCHAT_DEV_URL\"
        }"
        create_credential "Google Chat - Development" "httpHeaderAuth" "$cred_data"

        # Update .env file
        sed -i "s|GCHAT_DEV_WEBHOOK=.*|GCHAT_DEV_WEBHOOK=$GCHAT_DEV_URL|" "$ENV_FILE"
    fi
}

# Configure Gitea API
configure_gitea() {
    print_info "Configuring Gitea API..."

    print_prompt "Enter Gitea URL (default: https://gitea.example.com):"
    read -r GITEA_URL
    GITEA_URL="${GITEA_URL:-https://gitea.example.com}"

    print_prompt "Enter Gitea API Token (or press Enter to skip):"
    read -rs GITEA_TOKEN
    echo

    if [ -n "$GITEA_TOKEN" ]; then
        cred_data="{
            \"baseUrl\": \"$GITEA_URL\",
            \"apiKey\": \"$GITEA_TOKEN\"
        }"
        create_credential "Gitea API" "httpHeaderAuth" "$cred_data"

        # Update .env file
        sed -i "s|GITEA_URL=.*|GITEA_URL=$GITEA_URL|" "$ENV_FILE"
        sed -i "s|GITEA_API_TOKEN=.*|GITEA_API_TOKEN=$GITEA_TOKEN|" "$ENV_FILE"
    fi
}

# Configure GCP Service Account
configure_gcp() {
    print_info "Configuring GCP Service Account..."

    print_prompt "Enter path to GCP Service Account JSON key file (or press Enter to skip):"
    read -r GCP_KEY_FILE

    if [ -n "$GCP_KEY_FILE" ] && [ -f "$GCP_KEY_FILE" ]; then
        # Read and encode the service account key
        GCP_KEY_CONTENT=$(cat "$GCP_KEY_FILE")
        GCP_KEY_BASE64=$(echo "$GCP_KEY_CONTENT" | base64 -w 0)

        # Parse the service account email from the JSON
        SERVICE_ACCOUNT_EMAIL=$(echo "$GCP_KEY_CONTENT" | grep -oP '"client_email":\s*"\K[^"]+')

        cred_data="{
            \"email\": \"$SERVICE_ACCOUNT_EMAIL\",
            \"privateKey\": $(echo "$GCP_KEY_CONTENT" | jq -Rs '.')
        }"
        create_credential "GCP Service Account" "googleApi" "$cred_data"

        # Update .env file
        sed -i "s|GCP_SERVICE_ACCOUNT_KEY=.*|GCP_SERVICE_ACCOUNT_KEY=$GCP_KEY_BASE64|" "$ENV_FILE"
        print_info "GCP Service Account configured"
    fi
}

# Configure SMTP Email
configure_smtp() {
    print_info "Configuring SMTP Email..."

    print_prompt "Enter SMTP Host (default: smtp.gmail.com):"
    read -r SMTP_HOST
    SMTP_HOST="${SMTP_HOST:-smtp.gmail.com}"

    print_prompt "Enter SMTP Port (default: 587):"
    read -r SMTP_PORT
    SMTP_PORT="${SMTP_PORT:-587}"

    print_prompt "Enter SMTP Username/Email:"
    read -r SMTP_USER

    if [ -n "$SMTP_USER" ]; then
        print_prompt "Enter SMTP Password/App Password:"
        read -rs SMTP_PASS
        echo

        print_prompt "Enter Sender Email (default: $SMTP_USER):"
        read -r SMTP_SENDER
        SMTP_SENDER="${SMTP_SENDER:-$SMTP_USER}"

        cred_data="{
            \"host\": \"$SMTP_HOST\",
            \"port\": $SMTP_PORT,
            \"user\": \"$SMTP_USER\",
            \"password\": \"$SMTP_PASS\",
            \"sender\": \"$SMTP_SENDER\",
            \"secure\": true
        }"
        create_credential "SMTP Email" "smtp" "$cred_data"

        # Update .env file
        sed -i "s|SMTP_HOST=.*|SMTP_HOST=$SMTP_HOST|" "$ENV_FILE"
        sed -i "s|SMTP_PORT=.*|SMTP_PORT=$SMTP_PORT|" "$ENV_FILE"
        sed -i "s|SMTP_USER=.*|SMTP_USER=$SMTP_USER|" "$ENV_FILE"
        sed -i "s|SMTP_PASS=.*|SMTP_PASS=$SMTP_PASS|" "$ENV_FILE"
        sed -i "s|SMTP_SENDER=.*|SMTP_SENDER=$SMTP_SENDER|" "$ENV_FILE"
    fi
}

# Configure JIRA (Optional)
configure_jira() {
    print_info "Configuring JIRA (Optional)..."

    print_prompt "Configure JIRA? (y/N):"
    read -r CONFIGURE_JIRA

    if [[ "$CONFIGURE_JIRA" =~ ^[Yy]$ ]]; then
        print_prompt "Enter JIRA URL (e.g., https://your-domain.atlassian.net):"
        read -r JIRA_URL

        print_prompt "Enter JIRA Email:"
        read -r JIRA_USER

        print_prompt "Enter JIRA API Token:"
        read -rs JIRA_TOKEN
        echo

        if [ -n "$JIRA_URL" ] && [ -n "$JIRA_USER" ] && [ -n "$JIRA_TOKEN" ]; then
            cred_data="{
                \"domain\": \"$(echo $JIRA_URL | sed 's|https://||' | sed 's|\.atlassian\.net||')\",
                \"email\": \"$JIRA_USER\",
                \"apiToken\": \"$JIRA_TOKEN\"
            }"
            create_credential "JIRA" "jira" "$cred_data"

            # Update .env file
            sed -i "s|JIRA_URL=.*|JIRA_URL=$JIRA_URL|" "$ENV_FILE"
            sed -i "s|JIRA_USER=.*|JIRA_USER=$JIRA_USER|" "$ENV_FILE"
            sed -i "s|JIRA_API_TOKEN=.*|JIRA_API_TOKEN=$JIRA_TOKEN|" "$ENV_FILE"
        fi
    fi
}

# Configure PagerDuty (Optional)
configure_pagerduty() {
    print_info "Configuring PagerDuty (Optional)..."

    print_prompt "Configure PagerDuty? (y/N):"
    read -r CONFIGURE_PD

    if [[ "$CONFIGURE_PD" =~ ^[Yy]$ ]]; then
        print_prompt "Enter PagerDuty API Key:"
        read -rs PD_API_KEY
        echo

        print_prompt "Enter PagerDuty Service ID:"
        read -r PD_SERVICE_ID

        print_prompt "Enter PagerDuty Escalation Policy ID:"
        read -r PD_POLICY_ID

        if [ -n "$PD_API_KEY" ]; then
            cred_data="{
                \"apiToken\": \"$PD_API_KEY\"
            }"
            create_credential "PagerDuty" "pagerDutyApi" "$cred_data"

            # Update .env file
            sed -i "s|PAGERDUTY_API_KEY=.*|PAGERDUTY_API_KEY=$PD_API_KEY|" "$ENV_FILE"
            sed -i "s|PAGERDUTY_SERVICE_ID=.*|PAGERDUTY_SERVICE_ID=$PD_SERVICE_ID|" "$ENV_FILE"
            sed -i "s|PAGERDUTY_ESCALATION_POLICY=.*|PAGERDUTY_ESCALATION_POLICY=$PD_POLICY_ID|" "$ENV_FILE"
        fi
    fi
}

# Configure Webhook API Key
configure_webhook_key() {
    print_info "Configuring Webhook Security..."

    WEBHOOK_KEY="${WEBHOOK_API_KEY}"
    if [ -z "$WEBHOOK_KEY" ]; then
        WEBHOOK_KEY=$(openssl rand -hex 32)
        sed -i "s|WEBHOOK_API_KEY=.*|WEBHOOK_API_KEY=$WEBHOOK_KEY|" "$ENV_FILE"
    fi

    cred_data="{
        \"headerName\": \"X-API-Key\",
        \"headerValue\": \"$WEBHOOK_KEY\"
    }"
    create_credential "Webhook API Key" "httpHeaderAuth" "$cred_data"

    print_info "Webhook API Key configured: $WEBHOOK_KEY"
}

# Configure GCS Buckets
configure_gcs_buckets() {
    print_info "Configuring GCS Evidence Buckets..."

    print_prompt "Enter GCS Evidence Bucket name (default: compliance-evidence-standard):"
    read -r GCS_BUCKET
    GCS_BUCKET="${GCS_BUCKET:-compliance-evidence-standard}"

    print_prompt "Enter GCS Critical Evidence Bucket name (default: compliance-evidence-immutable):"
    read -r GCS_CRITICAL_BUCKET
    GCS_CRITICAL_BUCKET="${GCS_CRITICAL_BUCKET:-compliance-evidence-immutable}"

    # Update .env file
    sed -i "s|GCS_EVIDENCE_BUCKET=.*|GCS_EVIDENCE_BUCKET=$GCS_BUCKET|" "$ENV_FILE"
    sed -i "s|GCS_EVIDENCE_BUCKET_CRITICAL=.*|GCS_EVIDENCE_BUCKET_CRITICAL=$GCS_CRITICAL_BUCKET|" "$ENV_FILE"

    print_info "GCS buckets configured"
}

# Main menu
main_menu() {
    while true; do
        echo ""
        echo "======================================="
        echo "   n8n Credential Configuration Menu"
        echo "======================================="
        echo "1) Configure All Credentials"
        echo "2) Configure Google Chat Webhooks"
        echo "3) Configure Gitea API"
        echo "4) Configure GCP Service Account"
        echo "5) Configure SMTP Email"
        echo "6) Configure JIRA (Optional)"
        echo "7) Configure PagerDuty (Optional)"
        echo "8) Configure Webhook Security"
        echo "9) Configure GCS Buckets"
        echo "0) Exit"
        echo ""
        print_prompt "Select an option:"
        read -r option

        case $option in
            1)
                configure_google_chat
                configure_gitea
                configure_gcp
                configure_smtp
                configure_webhook_key
                configure_gcs_buckets
                configure_jira
                configure_pagerduty
                ;;
            2) configure_google_chat ;;
            3) configure_gitea ;;
            4) configure_gcp ;;
            5) configure_smtp ;;
            6) configure_jira ;;
            7) configure_pagerduty ;;
            8) configure_webhook_key ;;
            9) configure_gcs_buckets ;;
            0)
                print_info "Configuration complete!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

# Check n8n availability
check_n8n() {
    print_info "Checking n8n availability..."

    if ! curl -s -o /dev/null -w "%{http_code}" "$N8N_URL/healthz" | grep -q "200"; then
        print_error "n8n is not accessible at $N8N_URL"
        print_error "Please ensure n8n is running: docker-compose -f docker-compose-n8n.yml up -d"
        exit 1
    fi

    print_info "n8n is accessible"
}

# Main execution
main() {
    print_info "Starting n8n Credential Configuration..."

    check_n8n
    main_menu
}

# Run main function
main "$@"