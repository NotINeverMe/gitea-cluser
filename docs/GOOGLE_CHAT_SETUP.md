# Google Chat Integration Setup Guide

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Creating Google Chat Spaces](#creating-google-chat-spaces)
- [Setting Up Webhooks](#setting-up-webhooks)
- [Message Card Formatting](#message-card-formatting)
- [Thread Management](#thread-management)
- [Testing Integration](#testing-integration)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)

## Overview

Google Chat serves as the primary notification channel for security events, compliance violations, and operational alerts in our DevSecOps platform. This guide covers setting up Google Chat spaces, configuring webhooks, and customizing alert formatting.

### Integration Architecture

```
┌──────────────┐      ┌─────────────┐      ┌──────────────────┐
│     n8n      │─────▶│  Webhook    │─────▶│  Google Chat     │
│  Workflows   │      │   Endpoint  │      │     Spaces       │
└──────────────┘      └─────────────┘      └──────────────────┘
                                                     │
                              ┌──────────────────────┼──────────────────────┐
                              ▼                      ▼                      ▼
                      ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
                      │   Security   │      │ Development  │      │  Operations  │
                      │    Space     │      │    Space     │      │    Space     │
                      └──────────────┘      └──────────────┘      └──────────────┘
```

## Prerequisites

### Requirements

1. **Google Workspace Account** with Google Chat enabled
2. **Space Manager** permissions in Google Chat
3. **Admin access** to n8n platform
4. **API access** enabled in Google Workspace

### Recommended Setup

- **Minimum 2 spaces**: Security and Development
- **Optional spaces**: Operations, Management, Compliance
- **Dedicated bot account** for webhook management

## Creating Google Chat Spaces

### Step 1: Create Security Space

1. **Open Google Chat**: https://chat.google.com
2. **Create Space**:
   - Click "+" next to "Spaces"
   - Choose "Create space"
   - Space name: `DevSecOps Security`
   - Description: "Critical security alerts and incident response"
   - Space type: Restricted (invite-only)

3. **Configure Space Settings**:
   ```
   Settings → Space settings:
   - History: On (for audit trail)
   - External users: Disabled
   - @mentions: Enabled
   - Threading: Enabled
   ```

4. **Add Members**:
   - Security team members
   - Incident response team
   - DevOps leads
   - Compliance officers

### Step 2: Create Development Space

1. **Create Space**:
   - Name: `DevSecOps Development`
   - Description: "Development alerts and non-critical notifications"
   - Space type: Restricted

2. **Add Members**:
   - Development team
   - QA engineers
   - Product owners

### Step 3: Optional Spaces

```yaml
Compliance Space:
  Name: "DevSecOps Compliance"
  Members: [Compliance team, Auditors]
  Purpose: CMMC/NIST compliance alerts

Operations Space:
  Name: "DevSecOps Operations"
  Members: [SRE team, Infrastructure team]
  Purpose: Performance and cost alerts

Management Space:
  Name: "DevSecOps Executive"
  Members: [CTO, CISO, Engineering Managers]
  Purpose: High-level summaries and metrics
```

## Setting Up Webhooks

### Step 1: Create Webhook for Security Space

1. **Open Security Space**
2. **Access Space Menu**:
   - Click space name at top
   - Select "Apps & integrations"

3. **Add Webhook**:
   ```
   Manage webhooks → Add webhook:
   - Name: "n8n Security Alerts"
   - Avatar URL: https://example.com/icons/security.png (optional)
   ```

4. **Copy Webhook URL**:
   ```
   https://chat.googleapis.com/v1/spaces/AAAABBBBCCCC/messages?key=AIzaSy...&token=...
   ```

5. **Save in n8n**:
   ```bash
   # Add to .env file
   GCHAT_SECURITY_WEBHOOK="https://chat.googleapis.com/v1/spaces/AAAABBBBCCCC/messages?key=AIzaSy...&token=..."
   ```

### Step 2: Create Webhook for Development Space

Repeat above steps with:
- Name: "n8n Development Alerts"
- Save as `GCHAT_DEV_WEBHOOK`

### Step 3: Webhook Security Best Practices

1. **Rotate Tokens Regularly**:
   ```bash
   # Quarterly rotation schedule
   # Document in password manager
   # Update n8n credentials
   ```

2. **Restrict Webhook Access**:
   - Store tokens in secure vault
   - Use environment variables
   - Never commit to version control

3. **Monitor Webhook Usage**:
   ```javascript
   // Add logging in n8n workflow
   console.log(`Webhook called: ${webhook_url.substring(0, 50)}...`);
   ```

## Message Card Formatting

### Basic Alert Card

```json
{
  "cardsV2": [{
    "cardId": "unique-card-id",
    "card": {
      "header": {
        "title": "🔴 Critical Security Alert",
        "subtitle": "Vulnerability Detected",
        "imageUrl": "https://fonts.gstatic.com/s/i/googlematerialicons/warning/v12/24px.svg"
      },
      "sections": [{
        "widgets": [{
          "textParagraph": {
            "text": "A critical vulnerability has been detected in production."
          }
        }]
      }]
    }
  }]
}
```

### Advanced Card with Actions

```json
{
  "cardsV2": [{
    "cardId": "alert-${timestamp}",
    "card": {
      "header": {
        "title": "⚠️ Security Event",
        "subtitle": "${event_type} - ${severity}",
        "imageUrl": "https://example.com/icons/security.png",
        "imageType": "CIRCLE"
      },
      "sections": [
        {
          "header": "Event Details",
          "widgets": [
            {
              "decoratedText": {
                "topLabel": "CVE ID",
                "text": "${cve_id}",
                "startIcon": {
                  "knownIcon": "DESCRIPTION"
                }
              }
            },
            {
              "decoratedText": {
                "topLabel": "Severity",
                "text": "${severity}",
                "startIcon": {
                  "knownIcon": "STAR"
                },
                "button": {
                  "text": "View CVE",
                  "onClick": {
                    "openLink": {
                      "url": "https://nvd.nist.gov/vuln/detail/${cve_id}"
                    }
                  }
                }
              }
            },
            {
              "decoratedText": {
                "topLabel": "Affected Component",
                "text": "${component}",
                "startIcon": {
                  "knownIcon": "MULTIPLE_PEOPLE"
                },
                "wrapText": true
              }
            }
          ]
        },
        {
          "header": "Required Actions",
          "widgets": [
            {
              "decoratedText": {
                "topLabel": "Remediation",
                "text": "${remediation}",
                "startIcon": {
                  "knownIcon": "TASK_ALT"
                }
              }
            },
            {
              "decoratedText": {
                "topLabel": "SLA",
                "text": "${sla_hours} hours",
                "startIcon": {
                  "knownIcon": "CLOCK"
                }
              }
            },
            {
              "buttonList": {
                "buttons": [
                  {
                    "text": "Create Ticket",
                    "onClick": {
                      "openLink": {
                        "url": "https://jira.example.com/create-issue"
                      }
                    }
                  },
                  {
                    "text": "View Details",
                    "onClick": {
                      "openLink": {
                        "url": "https://security.example.com/event/${event_id}"
                      }
                    }
                  },
                  {
                    "text": "Acknowledge",
                    "onClick": {
                      "action": {
                        "function": "acknowledge",
                        "parameters": [{
                          "key": "event_id",
                          "value": "${event_id}"
                        }]
                      }
                    }
                  }
                ]
              }
            }
          ]
        },
        {
          "header": "Compliance Impact",
          "collapsible": true,
          "widgets": [
            {
              "textParagraph": {
                "text": "Controls Affected: ${compliance_controls}\nFrameworks: CMMC 2.0, NIST 800-171"
              }
            }
          ]
        }
      ]
    }
  }]
}
```

### Severity-Based Formatting

```javascript
// n8n Function Node for Dynamic Formatting
function getCardColor(severity) {
  const colors = {
    'CRITICAL': '#FF0000',  // Red
    'HIGH': '#FF6600',      // Orange
    'MEDIUM': '#FFCC00',    // Yellow
    'LOW': '#00CC00',       // Green
    'INFO': '#0066CC'       // Blue
  };
  return colors[severity] || '#808080';
}

function getIcon(eventType) {
  const icons = {
    'vulnerability': '🔴',
    'compliance': '⚖️',
    'incident': '🚨',
    'cost': '💰',
    'performance': '📊'
  };
  return icons[eventType] || '📌';
}

// Generate card based on event
const card = {
  header: {
    title: `${getIcon(eventType)} ${eventType.toUpperCase()} Alert`,
    subtitle: `Severity: ${severity}`,
    imageUrl: `https://example.com/status-${severity.toLowerCase()}.png`
  },
  sections: generateSections(eventData)
};
```

## Thread Management

### Creating Threaded Conversations

```json
{
  "text": "Follow-up on security incident",
  "thread": {
    "name": "spaces/SPACE_ID/threads/THREAD_ID"
  },
  "cardsV2": [...]
}
```

### Thread Naming Convention

```
Pattern: [TYPE]-[DATE]-[ID]
Examples:
- INCIDENT-20240115-001
- VULN-20240115-CVE-2024-12345
- COMPLIANCE-20240115-AC.L2-3.1.1
```

### Automated Thread Creation

```javascript
// n8n Code for thread management
const threadKey = `${eventType}-${date}-${eventId}`;
const threadName = `spaces/${spaceId}/threads/${threadKey}`;

// Store thread mapping
const threadMapping = {
  eventId: eventId,
  threadName: threadName,
  created: new Date().toISOString(),
  status: 'open'
};

// Send to thread
const message = {
  thread: { name: threadName },
  text: updateText,
  cardsV2: [updateCard]
};
```

## Testing Integration

### Manual Testing

1. **Test Webhook Connectivity**:
```bash
curl -X POST "$GCHAT_SECURITY_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Test message from n8n integration"
  }'
```

2. **Test Card Formatting**:
```bash
curl -X POST "$GCHAT_SECURITY_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d @test-card.json
```

### Automated Testing

```bash
# Run n8n test script
./scripts/test-n8n-workflows.sh interactive

# Select options:
# 1) Test Critical Alert → Security Space
# 2) Test Info Alert → Dev Space
# 3) Test Thread Creation
# 4) Test Card Actions
```

### Test Scenarios

```yaml
Critical Security Alert:
  Space: Security
  Card: Red header, immediate action required
  Thread: Auto-created
  Mentions: @security-team

Compliance Violation:
  Space: Security, Compliance
  Card: Yellow header, remediation steps
  Thread: Linked to control ID
  Attachments: Evidence report

Cost Alert:
  Space: Operations, Management
  Card: Charts and graphs
  Thread: Monthly cost thread
  Actions: Approve/Deny buttons
```

## Advanced Features

### Interactive Cards with Actions

```json
{
  "cardsV2": [{
    "card": {
      "sections": [{
        "widgets": [{
          "buttonList": {
            "buttons": [{
              "text": "Approve",
              "onClick": {
                "action": {
                  "function": "approveAction",
                  "parameters": [{
                    "key": "requestId",
                    "value": "REQ-12345"
                  }],
                  "interaction": "OPEN_DIALOG"
                }
              }
            }]
          }
        }]
      }]
    }
  }]
}
```

### Slash Commands

```javascript
// Register slash commands in Google Chat
const commands = {
  "/status": "Get system status",
  "/incidents": "List active incidents",
  "/acknowledge <id>": "Acknowledge alert",
  "/escalate <id>": "Escalate to management"
};
```

### Scheduled Reports

```javascript
// n8n Cron Node configuration
{
  "cronExpression": "0 9 * * 1", // Every Monday at 9 AM
  "message": {
    "text": "Weekly Security Summary",
    "cardsV2": [{
      "card": {
        "header": {
          "title": "📊 Weekly Security Report",
          "subtitle": `Week of ${weekStart}`
        },
        "sections": [
          generateMetricsSection(),
          generateIncidentsSection(),
          generateComplianceSection()
        ]
      }
    }]
  }
}
```

### Mention Handling

```json
{
  "text": "<users/all> Critical security incident detected!",
  "cardsV2": [...],
  "annotations": [{
    "type": "USER_MENTION",
    "startIndex": 0,
    "length": 11,
    "userMention": {
      "user": {
        "name": "users/all"
      }
    }
  }]
}
```

## Troubleshooting

### Common Issues

#### 1. Webhook Returns 403 Forbidden

**Cause**: Invalid token or webhook disabled
**Solution**:
```bash
# Regenerate webhook in Google Chat
# Update n8n credentials
# Test with curl
```

#### 2. Messages Not Appearing

**Cause**: Rate limiting or formatting error
**Solution**:
```javascript
// Add delay between messages
await sleep(1000); // 1 second delay

// Validate JSON
JSON.parse(messagePayload); // Will throw if invalid
```

#### 3. Card Rendering Issues

**Cause**: Invalid card structure
**Solution**:
```javascript
// Use Google Chat Card Builder
// https://developers.google.com/chat/ui/widgets

// Validate card schema
const validateCard = (card) => {
  if (!card.header) throw new Error('Missing header');
  if (!card.sections) throw new Error('Missing sections');
  return true;
};
```

#### 4. Thread Synchronization

**Cause**: Thread key mismatch
**Solution**:
```javascript
// Store thread keys in database
const threadKey = crypto.createHash('md5')
  .update(`${eventType}-${eventId}`)
  .digest('hex');
```

### Rate Limits

Google Chat API limits:
- **60 requests per minute** per webhook
- **25 KB** maximum message size
- **100 cards** per message
- **500 widgets** per card

Implement rate limiting:
```javascript
// n8n rate limiter
const rateLimiter = {
  maxRequests: 50,
  timeWindow: 60000, // 1 minute
  queue: [],

  async send(message) {
    if (this.queue.length >= this.maxRequests) {
      await sleep(this.timeWindow / this.maxRequests);
    }
    this.queue.push(Date.now());
    // Remove old entries
    this.queue = this.queue.filter(t =>
      Date.now() - t < this.timeWindow
    );
    return sendToGoogleChat(message);
  }
};
```

### Debugging

Enable verbose logging in n8n:
```javascript
// n8n Function node
console.log('Sending to Google Chat:', {
  space: spaceName,
  messageType: card.header.title,
  timestamp: new Date().toISOString()
});

// Log response
console.log('Google Chat response:', response.status);
```

## Best Practices

### 1. Message Priority

```yaml
Critical (Red):
  - Production outages
  - Security breaches
  - Data loss events
  Space: Security
  Mentions: @all

High (Orange):
  - Failed deployments
  - Performance degradation
  - Compliance violations
  Space: Security, Operations

Medium (Yellow):
  - Non-critical vulnerabilities
  - Configuration drift
  - Cost overruns
  Space: Development, Operations

Low (Green):
  - Successful deployments
  - Audit completions
  - Metrics reports
  Space: Development
```

### 2. Message Frequency

- **Batch similar alerts** (max 5 per message)
- **Implement quiet hours** (optional)
- **Use threads** for related events
- **Daily summary** for non-critical items

### 3. Card Design

- **Keep headers concise** (< 40 characters)
- **Use icons consistently**
- **Limit to 3-4 sections**
- **Include actionable buttons**
- **Add timestamp** in footer

### 4. Space Management

- **Regular membership review**
- **Archive old threads** (quarterly)
- **Document space purposes**
- **Set clear notification expectations**

## Integration with Other Tools

### JIRA Integration

```javascript
// Add JIRA ticket link to card
{
  "widgets": [{
    "buttons": [{
      "text": "View in JIRA",
      "onClick": {
        "openLink": {
          "url": `https://jira.example.com/browse/${ticketId}`
        }
      }
    }]
  }]
}
```

### Slack Bridging (Optional)

```javascript
// Forward critical alerts to Slack
if (severity === 'CRITICAL') {
  await sendToSlack({
    channel: '#security-alerts',
    text: `Google Chat Alert: ${message.text}`,
    attachments: convertCardToSlackFormat(card)
  });
}
```

### Email Escalation

```javascript
// Escalate if no acknowledgment in 15 minutes
setTimeout(async () => {
  if (!acknowledged) {
    await sendEmail({
      to: 'security-escalation@example.com',
      subject: `Unacknowledged Alert: ${eventId}`,
      body: generateEmailFromCard(card)
    });
  }
}, 15 * 60 * 1000);
```

## Resources

- [Google Chat API Documentation](https://developers.google.com/chat)
- [Card Builder Tool](https://developers.google.com/chat/ui/widgets)
- [Webhook Guide](https://developers.google.com/chat/how-tos/webhooks)
- [Best Practices](https://developers.google.com/chat/best-practices)
- [Rate Limits](https://developers.google.com/chat/limits)