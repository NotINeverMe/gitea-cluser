#!/bin/bash
# Google Chat Webhook Configuration for Security Alerts
# CMMC 2.0: SI.L2-3.14.3 - Monitor security alerts
# NIST SP 800-171: 3.14.3 - Monitor system security alerts

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/.gchat-config"
ENV_FILE="${PROJECT_ROOT}/.env"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to create Google Chat webhook in Google Cloud
create_gchat_webhook() {
    print_status "Google Chat Webhook Setup Instructions"
    echo ""
    echo "To create a Google Chat webhook:"
    echo ""
    echo "1. Open Google Chat (chat.google.com)"
    echo "2. Create or select a space for security alerts"
    echo "3. Click the space name → 'Apps & integrations'"
    echo "4. Click '+ Add webhooks'"
    echo "5. Configure the webhook:"
    echo "   - Name: 'Gitea Security Alerts'"
    echo "   - Avatar URL: (optional)"
    echo "6. Copy the webhook URL"
    echo ""

    read -p "Enter your Google Chat webhook URL: " WEBHOOK_URL

    if [[ ! "$WEBHOOK_URL" =~ ^https://chat.googleapis.com/v1/spaces/.*/messages\?key=.*$ ]]; then
        print_error "Invalid webhook URL format"
        return 1
    fi

    echo "GCHAT_WEBHOOK_URL=${WEBHOOK_URL}" >> "$ENV_FILE"
    print_success "Webhook URL saved to .env file"
}

# Function to test webhook
test_webhook() {
    local webhook_url="$1"

    print_status "Testing webhook connection..."

    # Create test message
    local test_message=$(cat << 'EOF'
{
  "cards": [{
    "header": {
      "title": "🔒 Security Alert Test",
      "subtitle": "Gitea DevSecOps Platform"
    },
    "sections": [{
      "widgets": [{
        "textParagraph": {
          "text": "<b>Test Message</b><br>This is a test of the security alert system."
        }
      }, {
        "keyValue": {
          "topLabel": "Status",
          "content": "Connection Successful",
          "icon": "CONFIRMATION"
        }
      }, {
        "keyValue": {
          "topLabel": "Timestamp",
          "content": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        }
      }, {
        "textParagraph": {
          "text": "<b>Compliance:</b> CMMC SI.L2-3.14.3, NIST 3.14.3"
        }
      }]
    }]
  }]
}
EOF
    )

    # Send test message
    response=$(curl -s -X POST "$webhook_url" \
        -H 'Content-Type: application/json' \
        -d "$test_message" 2>&1)

    if [[ "$response" == *"error"* ]]; then
        print_error "Failed to send test message: $response"
        return 1
    else
        print_success "Test message sent successfully!"
        return 0
    fi
}

# Function to create alert templates
create_alert_templates() {
    print_status "Creating alert templates..."

    local template_dir="${PROJECT_ROOT}/config/gchat-templates"
    mkdir -p "$template_dir"

    # Critical security alert template
    cat > "${template_dir}/critical-alert.json" << 'EOF'
{
  "cards": [{
    "header": {
      "title": "🚨 CRITICAL SECURITY ALERT",
      "subtitle": "{{repository}} - {{branch}}",
      "imageUrl": "https://www.gstatic.com/images/icons/material/system/2x/warning_red_48dp.png"
    },
    "sections": [{
      "widgets": [{
        "textParagraph": {
          "text": "<b><font color=\"#ff0000\">IMMEDIATE ACTION REQUIRED</font></b>"
        }
      }, {
        "keyValue": {
          "topLabel": "Severity",
          "content": "CRITICAL",
          "icon": "DESCRIPTION",
          "button": {
            "textButton": {
              "text": "VIEW DETAILS",
              "onClick": {
                "openLink": {
                  "url": "{{details_url}}"
                }
              }
            }
          }
        }
      }, {
        "keyValue": {
          "topLabel": "Finding Type",
          "content": "{{finding_type}}"
        }
      }, {
        "keyValue": {
          "topLabel": "Affected Component",
          "content": "{{component}}"
        }
      }, {
        "textParagraph": {
          "text": "<b>Description:</b><br>{{description}}"
        }
      }, {
        "textParagraph": {
          "text": "<b>Remediation:</b><br>{{remediation}}"
        }
      }, {
        "textParagraph": {
          "text": "<b>Compliance Impact:</b><br>{{compliance_impact}}"
        }
      }, {
        "buttons": [{
          "textButton": {
            "text": "ACKNOWLEDGE",
            "onClick": {
              "openLink": {
                "url": "{{acknowledge_url}}"
              }
            }
          }
        }, {
          "textButton": {
            "text": "CREATE INCIDENT",
            "onClick": {
              "openLink": {
                "url": "{{incident_url}}"
              }
            }
          }
        }]
      }]
    }]
  }]
}
EOF

    # High severity alert template
    cat > "${template_dir}/high-alert.json" << 'EOF'
{
  "cards": [{
    "header": {
      "title": "⚠️ High Security Finding",
      "subtitle": "{{repository}} - {{branch}}"
    },
    "sections": [{
      "widgets": [{
        "keyValue": {
          "topLabel": "Severity",
          "content": "HIGH",
          "contentMultiline": false
        }
      }, {
        "keyValue": {
          "topLabel": "Scanner",
          "content": "{{scanner}}"
        }
      }, {
        "keyValue": {
          "topLabel": "Findings Count",
          "content": "{{count}}"
        }
      }, {
        "textParagraph": {
          "text": "{{summary}}"
        }
      }, {
        "buttons": [{
          "textButton": {
            "text": "VIEW REPORT",
            "onClick": {
              "openLink": {
                "url": "{{report_url}}"
              }
            }
          }
        }]
      }]
    }]
  }]
}
EOF

    # Compliance violation template
    cat > "${template_dir}/compliance-violation.json" << 'EOF'
{
  "cards": [{
    "header": {
      "title": "📋 Compliance Violation Detected",
      "subtitle": "{{compliance_framework}}"
    },
    "sections": [{
      "widgets": [{
        "keyValue": {
          "topLabel": "Control",
          "content": "{{control_id}}"
        }
      }, {
        "keyValue": {
          "topLabel": "Requirement",
          "content": "{{requirement}}"
        }
      }, {
        "textParagraph": {
          "text": "<b>Violation:</b><br>{{violation_description}}"
        }
      }, {
        "textParagraph": {
          "text": "<b>Required Action:</b><br>{{required_action}}"
        }
      }, {
        "keyValue": {
          "topLabel": "Evidence Hash",
          "content": "{{evidence_hash}}"
        }
      }]
    }]
  }]
}
EOF

    # Daily summary template
    cat > "${template_dir}/daily-summary.json" << 'EOF'
{
  "cards": [{
    "header": {
      "title": "📊 Daily Security Summary",
      "subtitle": "{{date}}"
    },
    "sections": [{
      "widgets": [{
        "textParagraph": {
          "text": "<b>Scan Statistics</b>"
        }
      }, {
        "keyValue": {
          "topLabel": "Total Scans",
          "content": "{{total_scans}}"
        }
      }, {
        "keyValue": {
          "topLabel": "Critical Findings",
          "content": "{{critical_count}}",
          "icon": "MULTIPLE_PEOPLE"
        }
      }, {
        "keyValue": {
          "topLabel": "High Findings",
          "content": "{{high_count}}"
        }
      }, {
        "keyValue": {
          "topLabel": "Medium Findings",
          "content": "{{medium_count}}"
        }
      }, {
        "textParagraph": {
          "text": "<b>Compliance Status</b>"
        }
      }, {
        "keyValue": {
          "topLabel": "CMMC Level 2",
          "content": "{{cmmc_compliance}}%"
        }
      }, {
        "keyValue": {
          "topLabel": "NIST 800-171",
          "content": "{{nist_compliance}}%"
        }
      }, {
        "buttons": [{
          "textButton": {
            "text": "VIEW DASHBOARD",
            "onClick": {
              "openLink": {
                "url": "{{dashboard_url}}"
              }
            }
          }
        }]
      }]
    }]
  }]
}
EOF

    print_success "Alert templates created in ${template_dir}"
}

# Function to configure alert routing
configure_alert_routing() {
    print_status "Configuring alert routing rules..."

    cat > "${PROJECT_ROOT}/config/alert-routing.yaml" << 'EOF'
# Alert Routing Configuration
# CMMC SI.L2-3.14.3 & NIST 3.14.3 Compliance

alert_routes:
  # Critical alerts - immediate notification
  critical:
    severity: CRITICAL
    channels:
      - google_chat
      - email
      - pagerduty
    escalation_time: 5m
    repeat_interval: 15m
    template: critical-alert.json

  # High severity alerts
  high:
    severity: HIGH
    channels:
      - google_chat
      - email
    escalation_time: 30m
    repeat_interval: 1h
    template: high-alert.json

  # Medium severity alerts
  medium:
    severity: MEDIUM
    channels:
      - google_chat
    escalation_time: 4h
    repeat_interval: 24h
    template: standard-alert.json

  # Low severity alerts
  low:
    severity: LOW
    channels:
      - daily_summary
    escalation_time: 24h
    repeat_interval: 7d
    template: summary.json

# Alert aggregation rules
aggregation:
  - name: duplicate_suppression
    window: 5m
    group_by:
      - finding_type
      - component
      - severity

  - name: noise_reduction
    threshold: 10
    window: 1h
    action: summarize

# Compliance-specific alerts
compliance_alerts:
  cmmc_violations:
    framework: "CMMC 2.0"
    controls:
      - CA.L2-3.12.4
      - RA.L2-3.11.2
      - SI.L2-3.14.2
    notification: immediate
    template: compliance-violation.json

  nist_violations:
    framework: "NIST SP 800-171"
    controls:
      - 3.11.2
      - 3.14.1
      - 3.14.2
      - 3.14.3
    notification: immediate
    template: compliance-violation.json

# Escalation matrix
escalation:
  level_1:
    recipients:
      - security-team
    time: 0m

  level_2:
    recipients:
      - security-lead
      - dev-lead
    time: 30m

  level_3:
    recipients:
      - ciso
      - engineering-director
    time: 2h

  level_4:
    recipients:
      - cto
      - compliance-officer
    time: 4h

# Quiet hours (optional)
quiet_hours:
  enabled: false
  start: "22:00"
  end: "07:00"
  timezone: "America/New_York"
  override_critical: true
EOF

    print_success "Alert routing configured"
}

# Function to create notification helper script
create_notification_helper() {
    print_status "Creating notification helper script..."

    cat > "${PROJECT_ROOT}/scripts/send-gchat-alert.sh" << 'EOF'
#!/bin/bash
# Helper script to send Google Chat alerts
# Usage: ./send-gchat-alert.sh <severity> <title> <message> [details_url]

set -euo pipefail

# Load configuration
source "$(dirname "$0")/../.env"

# Check webhook URL
if [ -z "${GCHAT_WEBHOOK_URL:-}" ]; then
    echo "Error: GCHAT_WEBHOOK_URL not configured"
    exit 1
fi

# Parse arguments
SEVERITY="${1:-INFO}"
TITLE="${2:-Security Alert}"
MESSAGE="${3:-No message provided}"
DETAILS_URL="${4:-}"

# Determine emoji and color based on severity
case "$SEVERITY" in
    CRITICAL)
        EMOJI="🚨"
        COLOR="#FF0000"
        ;;
    HIGH)
        EMOJI="⚠️"
        COLOR="#FFA500"
        ;;
    MEDIUM)
        EMOJI="⚡"
        COLOR="#FFFF00"
        ;;
    LOW)
        EMOJI="ℹ️"
        COLOR="#0000FF"
        ;;
    *)
        EMOJI="✅"
        COLOR="#00FF00"
        ;;
esac

# Build JSON payload
PAYLOAD=$(cat << JSON
{
  "cards": [{
    "header": {
      "title": "${EMOJI} ${TITLE}",
      "subtitle": "Severity: ${SEVERITY}"
    },
    "sections": [{
      "widgets": [{
        "textParagraph": {
          "text": "${MESSAGE}"
        }
      }, {
        "keyValue": {
          "topLabel": "Timestamp",
          "content": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        }
      }
JSON
)

# Add details URL if provided
if [ -n "$DETAILS_URL" ]; then
    PAYLOAD="${PAYLOAD}, {
        \"buttons\": [{
          \"textButton\": {
            \"text\": \"VIEW DETAILS\",
            \"onClick\": {
              \"openLink\": {
                \"url\": \"${DETAILS_URL}\"
              }
            }
          }
        }]
      }"
fi

# Close JSON structure
PAYLOAD="${PAYLOAD}]
    }]
  }
}"

# Send alert
curl -s -X POST "$GCHAT_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD"

echo "Alert sent successfully"
EOF

    chmod +x "${PROJECT_ROOT}/scripts/send-gchat-alert.sh"
    print_success "Notification helper script created"
}

# Function to configure Gitea Actions integration
configure_gitea_integration() {
    print_status "Configuring Gitea Actions integration..."

    cat > "${PROJECT_ROOT}/.gitea/actions/send-alert/action.yml" << 'EOF'
name: 'Send Google Chat Alert'
description: 'Send security alert to Google Chat'
inputs:
  severity:
    description: 'Alert severity (CRITICAL, HIGH, MEDIUM, LOW)'
    required: true
  title:
    description: 'Alert title'
    required: true
  message:
    description: 'Alert message'
    required: true
  details_url:
    description: 'URL for more details'
    required: false
  webhook_url:
    description: 'Google Chat webhook URL'
    required: true
runs:
  using: 'composite'
  steps:
    - name: Send Alert
      shell: bash
      env:
        WEBHOOK_URL: ${{ inputs.webhook_url }}
      run: |
        # Create alert payload
        PAYLOAD=$(cat << JSON
        {
          "cards": [{
            "header": {
              "title": "${{ inputs.title }}",
              "subtitle": "Severity: ${{ inputs.severity }}"
            },
            "sections": [{
              "widgets": [{
                "textParagraph": {
                  "text": "${{ inputs.message }}"
                }
              }, {
                "keyValue": {
                  "topLabel": "Repository",
                  "content": "${{ github.repository }}"
                }
              }, {
                "keyValue": {
                  "topLabel": "Branch",
                  "content": "${{ github.ref_name }}"
                }
              }, {
                "keyValue": {
                  "topLabel": "Commit",
                  "content": "${{ github.sha }}"
                }
              }, {
                "buttons": [{
                  "textButton": {
                    "text": "VIEW WORKFLOW",
                    "onClick": {
                      "openLink": {
                        "url": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
                      }
                    }
                  }
                }]
              }]
            }]
          }]
        }
        JSON
        )

        # Send to Google Chat
        curl -X POST "$WEBHOOK_URL" \
          -H 'Content-Type: application/json' \
          -d "$PAYLOAD"
EOF

    print_success "Gitea Actions integration configured"
}

# Main menu
show_menu() {
    echo ""
    echo "Google Chat Webhook Configuration"
    echo "================================="
    echo "1. Create new Google Chat webhook"
    echo "2. Test existing webhook"
    echo "3. Create alert templates"
    echo "4. Configure alert routing"
    echo "5. Setup Gitea integration"
    echo "6. Full setup (all of the above)"
    echo "7. Exit"
    echo ""
    read -p "Select option (1-7): " choice

    case $choice in
        1)
            create_gchat_webhook
            ;;
        2)
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                if [ -n "${GCHAT_WEBHOOK_URL:-}" ]; then
                    test_webhook "$GCHAT_WEBHOOK_URL"
                else
                    print_error "No webhook URL found in .env file"
                fi
            else
                print_error ".env file not found"
            fi
            ;;
        3)
            create_alert_templates
            ;;
        4)
            configure_alert_routing
            ;;
        5)
            configure_gitea_integration
            create_notification_helper
            ;;
        6)
            create_gchat_webhook
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                if [ -n "${GCHAT_WEBHOOK_URL:-}" ]; then
                    test_webhook "$GCHAT_WEBHOOK_URL"
                fi
            fi
            create_alert_templates
            configure_alert_routing
            configure_gitea_integration
            create_notification_helper
            print_success "Full Google Chat integration complete!"
            ;;
        7)
            echo "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid option"
            show_menu
            ;;
    esac
}

# Main execution
main() {
    echo "============================================"
    echo "Google Chat Security Alert Configuration"
    echo "CMMC SI.L2-3.14.3 & NIST 3.14.3 Compliance"
    echo "============================================"

    # Check for .env file
    if [ ! -f "$ENV_FILE" ]; then
        print_warning ".env file not found. Run setup-phase1a.sh first."
    fi

    show_menu
}

# Run main function
main "$@"