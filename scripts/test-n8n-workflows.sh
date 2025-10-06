#!/bin/bash

# n8n Workflow Testing Script
# Tests all security event types with sample payloads

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
TEST_DIR="$PROJECT_ROOT/tests/sample-events"

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

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    print_error ".env file not found. Please run setup-n8n.sh first."
    exit 1
fi

# n8n webhook configuration
WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:5678/webhook/security-events}"
WEBHOOK_KEY="${WEBHOOK_API_KEY}"

if [ -z "$WEBHOOK_KEY" ]; then
    print_error "Webhook API key not found. Please configure credentials first."
    exit 1
fi

# Create test event payloads
create_test_payloads() {
    print_info "Creating test event payloads..."

    mkdir -p "$TEST_DIR"

    # 1. Vulnerability Detection Event
    cat > "$TEST_DIR/vulnerability-critical.json" << 'EOF'
{
  "event_type": "vulnerability",
  "severity": "CRITICAL",
  "cve_id": "CVE-2024-12345",
  "cvss_score": 9.8,
  "component": "org.apache.log4j:log4j-core:2.14.0",
  "scanner": "trivy",
  "repository": "backend-api",
  "image": "backend-api:v1.2.3",
  "description": "Remote code execution vulnerability in Log4j",
  "affected_files": [
    "/app/lib/log4j-core-2.14.0.jar"
  ],
  "remediation": "Upgrade to log4j-core version 2.17.1 or later",
  "compliance_controls": ["AC.L2-3.1.1", "SI.L2-3.14.1"],
  "timestamp": "2024-01-15T10:30:00Z"
}
EOF

    # 2. Compliance Violation Event
    cat > "$TEST_DIR/compliance-violation.json" << 'EOF'
{
  "event_type": "compliance",
  "framework": "CMMC_2.0",
  "control_id": "AC.L2-3.1.1",
  "violation_type": "missing_control",
  "resource": "gcp-project-123/compute-instance-xyz",
  "scanner": "cloud-custodian",
  "description": "Instance lacks required access control configuration",
  "evidence": {
    "expected": "MFA enabled for all administrative access",
    "actual": "MFA not configured",
    "gap": "Missing multi-factor authentication"
  },
  "impact": "HIGH",
  "remediation_required": true,
  "timestamp": "2024-01-15T10:35:00Z"
}
EOF

    # 3. Security Gate Failure Event
    cat > "$TEST_DIR/gate-failure.json" << 'EOF'
{
  "event_type": "gate_failure",
  "pipeline_name": "main-deployment-pipeline",
  "stage": "security-scan",
  "gate_type": "security_scan",
  "build_id": "build-789456",
  "commit_sha": "a1b2c3d4e5f6",
  "branch": "main",
  "failure_reason": "Critical vulnerabilities detected: 3 CRITICAL, 7 HIGH",
  "scan_results": {
    "vulnerabilities": {
      "critical": 3,
      "high": 7,
      "medium": 15,
      "low": 22
    },
    "compliance": {
      "passed": 45,
      "failed": 8
    }
  },
  "repository": "backend-api",
  "timestamp": "2024-01-15T10:40:00Z"
}
EOF

    # 4. Security Incident Event
    cat > "$TEST_DIR/incident-detected.json" << 'EOF'
{
  "event_type": "incident",
  "incident_type": "data_breach",
  "severity": "CRITICAL",
  "affected_systems": ["database-prod", "api-gateway", "user-service"],
  "indicators_of_compromise": [
    "Unusual database queries from IP 192.168.1.100",
    "Large data transfer to external IP",
    "Modified audit log entries"
  ],
  "detection_source": "SIEM",
  "initial_detection_time": "2024-01-15T10:15:00Z",
  "description": "Potential data exfiltration detected from production database",
  "affected_data": {
    "records": 50000,
    "data_types": ["PII", "financial"],
    "classification": "CONFIDENTIAL"
  },
  "response_required": "IMMEDIATE",
  "timestamp": "2024-01-15T10:45:00Z"
}
EOF

    # 5. Cost Threshold Alert Event
    cat > "$TEST_DIR/cost-alert.json" << 'EOF'
{
  "event_type": "cost_alert",
  "cost_center": "engineering-prod",
  "current_monthly_cost": 45000,
  "projected_monthly_cost": 65000,
  "budget_limit": 50000,
  "currency": "USD",
  "top_cost_resources": [
    {
      "name": "compute-cluster-prod",
      "type": "compute",
      "cost": 25000,
      "utilization": 15,
      "recommendation": "Downsize or use spot instances"
    },
    {
      "name": "storage-archive",
      "type": "storage",
      "cost": 8000,
      "last_accessed": 45,
      "recommendation": "Move to cold storage"
    },
    {
      "name": "network-egress",
      "type": "network",
      "cost": 12000,
      "egress_gb": 500,
      "recommendation": "Implement CDN caching"
    }
  ],
  "alert_threshold": "90%",
  "timestamp": "2024-01-15T10:50:00Z"
}
EOF

    # 6. Medium Severity Vulnerability (for different workflow path)
    cat > "$TEST_DIR/vulnerability-medium.json" << 'EOF'
{
  "event_type": "vulnerability",
  "severity": "MEDIUM",
  "cve_id": "CVE-2024-98765",
  "cvss_score": 5.3,
  "component": "express:4.17.1",
  "scanner": "snyk",
  "repository": "frontend-app",
  "description": "Regular expression denial of service",
  "remediation": "Upgrade to express version 4.18.2",
  "compliance_controls": ["SI.L2-3.14.1"],
  "timestamp": "2024-01-15T10:55:00Z"
}
EOF

    # 7. Ransomware Incident
    cat > "$TEST_DIR/incident-ransomware.json" << 'EOF'
{
  "event_type": "incident",
  "incident_type": "ransomware",
  "severity": "CRITICAL",
  "affected_systems": ["file-server-01", "backup-server", "workstation-pool"],
  "indicators_of_compromise": [
    "Files encrypted with .locked extension",
    "Ransom note found in multiple directories",
    "Suspicious process: crypto.exe",
    "Network connections to known C2 servers"
  ],
  "detection_source": "EDR",
  "initial_detection_time": "2024-01-15T11:00:00Z",
  "description": "Ransomware attack detected, multiple systems affected",
  "ransom_demand": {
    "amount": 500000,
    "currency": "USD",
    "bitcoin_address": "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
  },
  "containment_status": "IN_PROGRESS",
  "timestamp": "2024-01-15T11:00:00Z"
}
EOF

    print_info "Test payloads created in $TEST_DIR"
}

# Send test event
send_test_event() {
    local event_file=$1
    local event_name=$2

    print_test "Sending $event_name..."

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $WEBHOOK_KEY" \
        -d @"$event_file" \
        "$WEBHOOK_URL" \
        -w "\nHTTP_STATUS:%{http_code}")

    http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d: -f2)
    body=$(echo "$response" | grep -v "HTTP_STATUS")

    if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
        print_info "✓ $event_name sent successfully"
        if [ -n "$body" ]; then
            echo "Response: $body"
        fi
    else
        print_error "✗ $event_name failed (HTTP $http_status)"
        echo "Response: $body"
    fi

    echo ""
    sleep 2  # Wait between requests
}

# Test all events
test_all_events() {
    print_info "Starting workflow tests..."
    echo ""

    # Check if n8n is accessible
    if ! curl -s -o /dev/null -w "%{http_code}" "http://localhost:5678/healthz" | grep -q "200"; then
        print_error "n8n is not accessible. Please ensure it's running."
        exit 1
    fi

    # Send each test event
    send_test_event "$TEST_DIR/vulnerability-critical.json" "Critical Vulnerability Detection"
    send_test_event "$TEST_DIR/compliance-violation.json" "Compliance Violation"
    send_test_event "$TEST_DIR/gate-failure.json" "Security Gate Failure"
    send_test_event "$TEST_DIR/incident-detected.json" "Security Incident - Data Breach"
    send_test_event "$TEST_DIR/cost-alert.json" "Cost Threshold Alert"
    send_test_event "$TEST_DIR/vulnerability-medium.json" "Medium Vulnerability Detection"
    send_test_event "$TEST_DIR/incident-ransomware.json" "Security Incident - Ransomware"

    print_info "All tests completed!"
}

# Test single event
test_single_event() {
    local event_type=$1

    case $event_type in
        vulnerability-critical)
            send_test_event "$TEST_DIR/vulnerability-critical.json" "Critical Vulnerability"
            ;;
        vulnerability-medium)
            send_test_event "$TEST_DIR/vulnerability-medium.json" "Medium Vulnerability"
            ;;
        compliance)
            send_test_event "$TEST_DIR/compliance-violation.json" "Compliance Violation"
            ;;
        gate-failure)
            send_test_event "$TEST_DIR/gate-failure.json" "Security Gate Failure"
            ;;
        incident-breach)
            send_test_event "$TEST_DIR/incident-detected.json" "Data Breach Incident"
            ;;
        incident-ransomware)
            send_test_event "$TEST_DIR/incident-ransomware.json" "Ransomware Incident"
            ;;
        cost)
            send_test_event "$TEST_DIR/cost-alert.json" "Cost Alert"
            ;;
        *)
            print_error "Unknown event type: $event_type"
            echo "Available types: vulnerability-critical, vulnerability-medium, compliance, gate-failure, incident-breach, incident-ransomware, cost"
            exit 1
            ;;
    esac
}

# Interactive test menu
interactive_menu() {
    while true; do
        echo ""
        echo "======================================="
        echo "    n8n Workflow Test Menu"
        echo "======================================="
        echo "1) Test Critical Vulnerability Detection"
        echo "2) Test Medium Vulnerability Detection"
        echo "3) Test Compliance Violation"
        echo "4) Test Security Gate Failure"
        echo "5) Test Data Breach Incident"
        echo "6) Test Ransomware Incident"
        echo "7) Test Cost Threshold Alert"
        echo "8) Run All Tests"
        echo "0) Exit"
        echo ""
        echo -n "Select a test to run: "
        read -r choice

        case $choice in
            1) test_single_event "vulnerability-critical" ;;
            2) test_single_event "vulnerability-medium" ;;
            3) test_single_event "compliance" ;;
            4) test_single_event "gate-failure" ;;
            5) test_single_event "incident-breach" ;;
            6) test_single_event "incident-ransomware" ;;
            7) test_single_event "cost" ;;
            8) test_all_events ;;
            0)
                print_info "Exiting test menu"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
    done
}

# View test payloads
view_payloads() {
    print_info "Available test payloads:"
    echo ""

    for file in "$TEST_DIR"/*.json; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            echo "📄 $filename"
            echo "---"
            jq -C '.' "$file" 2>/dev/null || cat "$file"
            echo ""
        fi
    done
}

# Main execution
main() {
    # Parse command line arguments
    case "${1:-}" in
        all)
            create_test_payloads
            test_all_events
            ;;
        view)
            create_test_payloads
            view_payloads
            ;;
        interactive|menu)
            create_test_payloads
            interactive_menu
            ;;
        *)
            if [ -n "${1:-}" ]; then
                create_test_payloads
                test_single_event "$1"
            else
                echo "n8n Workflow Test Script"
                echo ""
                echo "Usage: $0 [command]"
                echo ""
                echo "Commands:"
                echo "  all              Run all tests"
                echo "  view             View all test payloads"
                echo "  interactive      Interactive test menu"
                echo "  menu             Same as interactive"
                echo "  <event-type>     Test specific event"
                echo ""
                echo "Event types:"
                echo "  vulnerability-critical   Critical vulnerability detection"
                echo "  vulnerability-medium     Medium vulnerability detection"
                echo "  compliance              Compliance violation"
                echo "  gate-failure            Security gate failure"
                echo "  incident-breach         Data breach incident"
                echo "  incident-ransomware     Ransomware incident"
                echo "  cost                    Cost threshold alert"
                echo ""
                echo "Examples:"
                echo "  $0 all                  # Run all tests"
                echo "  $0 interactive          # Open interactive menu"
                echo "  $0 vulnerability-critical  # Test critical vulnerability"
                echo ""
                exit 0
            fi
            ;;
    esac
}

# Run main function
main "$@"