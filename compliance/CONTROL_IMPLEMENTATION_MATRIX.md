# Control Implementation Matrix
## Gitea DevSecOps Platform - Complete Control-to-Tool Mapping

**Document Version**: 1.0
**Date**: 2025-10-05
**Compliance Frameworks**: CMMC 2.0 Level 2, NIST SP 800-171 Rev. 2, NIST SP 800-53 Rev. 5
**Authorization Boundary**: Gitea DevSecOps Platform on GCP

---

## Executive Summary

This Control Implementation Matrix provides a complete mapping of all 34 tools in the Gitea DevSecOps platform to specific CMMC 2.0 Level 2, NIST SP 800-171 Rev. 2, and NIST SP 800-53 Rev. 5 controls. It documents implementation details, evidence collection procedures, testing methods, and responsible parties for each control.

**Coverage Summary**:
- Total Controls Mapped: 110 (NIST SP 800-171 Rev. 2)
- Automated Coverage: 89% (98/110 controls)
- Manual Coverage: 11% (12/110 controls)
- Tools Deployed: 34 integrated security and compliance tools

---

## ACCESS CONTROL (AC) - NIST SP 800-171 §3.1

### AC.L2-3.1.1 - Limit system access to authorized users

**NIST SP 800-171 Rev. 2 Citation**: §3.1.1
**NIST SP 800-53 Rev. 5 Mapping**: AC-2, AC-3, AC-6
**CMMC Level**: 2
**Practice**: AC.L2-3.1.1

**Implementation Description**:
Access to the Gitea DevSecOps platform is restricted to authorized users through role-based access control (RBAC) implemented in Gitea and GCP IAM. User accounts are provisioned only after approval through formal access request procedures documented in the SSP.

**Implementing Tools**:
1. **Gitea** (Primary)
   - Built-in user authentication and RBAC
   - Organization-level and repository-level permissions
   - OAuth2/OIDC integration with enterprise IdP
   - Configuration: Minimum password length 14 characters, complexity requirements enforced

2. **GCP Cloud IAM** (Supporting)
   - Project-level access controls
   - Service account management with least privilege
   - Workload identity federation for service-to-service auth

**Technical Configuration**:
```yaml
# Gitea app.ini configuration
[security]
MIN_PASSWORD_LENGTH = 14
PASSWORD_COMPLEXITY = lower,upper,digit,spec
PASSWORD_CHECK_PWN = true
LOGIN_REMEMBER_DAYS = 7
COOKIE_SECURE = true
COOKIE_HTTP_ONLY = true

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true
DEFAULT_ORG_MEMBER_VISIBLE = false
```

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/access-control/ac-3.1.1/
- **Collection Frequency**: Daily
- **Artifacts**:
  - User account inventory (CSV export from Gitea API)
  - Access log extracts (JSON from Cloud Logging)
  - RBAC permission matrix (automated export)
  - Session management logs

**Collection Procedure**:
```bash
# Daily evidence collection script
curl -H "Authorization: token ${GITEA_TOKEN}" \
  https://gitea.internal/api/v1/admin/users | \
  jq -r '.[] | {username, email, is_admin, last_login}' | \
  tee /tmp/user_inventory.json | \
  sha256sum > /tmp/user_inventory.json.sha256

gsutil cp /tmp/user_inventory.json \
  gs://compliance-evidence-store/access-control/ac-3.1.1/$(date +%Y%m%d)/
gsutil cp /tmp/user_inventory.json.sha256 \
  gs://compliance-evidence-store/access-control/ac-3.1.1/$(date +%Y%m%d)/
```

**Testing Procedure**:
1. Attempt unauthorized access to Gitea web interface (expect: denied)
2. Attempt access with valid credentials (expect: granted with appropriate permissions)
3. Verify session timeout after 30 minutes of inactivity
4. Review access logs for anomalies

**Responsible Party**: Security Operations Team
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-01
**Next Review**: 2025-11-01

---

### AC.L2-3.1.2 - Limit system access to types of transactions and functions

**NIST SP 800-171 Rev. 2 Citation**: §3.1.2
**NIST SP 800-53 Rev. 5 Mapping**: AC-3(7), AC-6(10)
**CMMC Level**: 2
**Practice**: AC.L2-3.1.2

**Implementation Description**:
Functional access controls are enforced through Gitea's granular permission system and Terraform Sentinel policy enforcement. Users can only perform transactions appropriate to their role (e.g., developers can create pull requests but not approve infrastructure changes; release managers can merge to main but not modify security policies).

**Implementing Tools**:
1. **Gitea** (Primary)
   - Repository-level protected branches
   - Pull request approval workflows
   - Code owner enforcement
   - Branch protection rules

2. **Terragrunt** (Supporting)
   - State file access control
   - Plan approval requirements

3. **Terraform Sentinel** (Commercial - Policy Enforcement)
   - Policy-as-code enforcement
   - Cost limit policies
   - Security baseline validation

**Technical Configuration**:
```yaml
# Gitea repository settings
protected_branches:
  - name: main
    required_approvals: 2
    dismiss_stale_reviews: true
    require_code_owner_reviews: true
    restrict_push:
      users: []
      teams: [release-managers]
    required_status_checks:
      - security/sast
      - security/container-scan
      - iac/policy-check

# Sentinel policy example
policy "restrict-compute-types" {
  enforcement_level = "hard-mandatory"
  source = "./policies/compute-restrictions.sentinel"
}
```

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/access-control/ac-3.1.2/
- **Collection Frequency**: On-change (git commits) + Weekly summaries
- **Artifacts**:
  - Branch protection configurations (JSON export)
  - Policy enforcement logs (Sentinel/Atlantis)
  - Function access matrix by role
  - Transaction approval records

**Testing Procedure**:
1. Attempt direct push to protected branch as developer (expect: denied)
2. Attempt to approve own pull request (expect: denied)
3. Attempt infrastructure change without policy compliance (expect: denied by Sentinel)
4. Verify code owner approval required for CODEOWNERS-protected paths

**Responsible Party**: DevOps Engineering
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-09-28
**Next Review**: 2025-10-28

---

### AC.L2-3.1.3 - Control the flow of CUI

**NIST SP 800-171 Rev. 2 Citation**: §3.1.3
**NIST SP 800-53 Rev. 5 Mapping**: AC-4, SC-7, SC-8
**CMMC Level**: 2
**Practice**: AC.L2-3.1.3

**Implementation Description**:
Controlled Unclassified Information (CUI) flow is managed through network segmentation, encryption, and data labeling. CUI repositories in Gitea are tagged with sensitivity labels and subject to enhanced access controls. All CUI data in transit is encrypted with TLS 1.3; at rest with AES-256 via Cloud KMS.

**Implementing Tools**:
1. **Cloud KMS** (Primary)
   - Customer-managed encryption keys (CMEK)
   - Envelope encryption for all stored objects
   - Key rotation every 90 days

2. **GCP VPC Service Controls** (Supporting)
   - Perimeter protection around CUI resources
   - Ingress/egress policies
   - Private Google Access only

3. **Caddy/Traefik** (Supporting)
   - TLS 1.3 termination
   - Minimum cipher suite enforcement
   - Certificate management

**Technical Configuration**:
```hcl
# Terraform configuration for CUI bucket
resource "google_storage_bucket" "cui_repos" {
  name          = "gitea-cui-repositories"
  location      = "US"

  encryption {
    default_kms_key_name = google_kms_crypto_key.cui_key.id
  }

  uniform_bucket_level_access = true

  retention_policy {
    retention_period = 220752000 # 7 years
    is_locked        = true
  }

  labels = {
    data_classification = "cui"
    compliance_scope    = "cmmc-level-2"
  }
}

# VPC Service Controls perimeter
resource "google_access_context_manager_service_perimeter" "cui_perimeter" {
  name   = "cui_protection_perimeter"
  title  = "CUI Data Protection Perimeter"

  status {
    restricted_services = [
      "storage.googleapis.com",
      "compute.googleapis.com"
    ]

    ingress_policies {
      ingress_from {
        sources {
          access_level = google_access_context_manager_access_level.cui_access.name
        }
      }
    }
  }
}
```

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/access-control/ac-3.1.3/
- **Collection Frequency**: Daily + Real-time alerts
- **Artifacts**:
  - VPC flow logs (filtered for CUI resources)
  - TLS handshake logs with cipher suite information
  - KMS key usage logs
  - Data exfiltration detection alerts

**Testing Procedure**:
1. Verify TLS 1.3 enforcement: `openssl s_client -connect gitea.internal:443 -tls1_2` (expect: failure)
2. Confirm encryption at rest: `gsutil ls -L gs://gitea-cui-repositories/` (verify kmsKeyName present)
3. Test VPC-SC perimeter: Attempt access from outside perimeter (expect: denied)
4. Verify key rotation: Check KMS key version history

**Responsible Party**: Cloud Security Architecture
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-02
**Next Review**: 2025-11-02

---

### AC.L2-3.1.5 - Employ the principle of least privilege

**NIST SP 800-171 Rev. 2 Citation**: §3.1.5
**NIST SP 800-53 Rev. 5 Mapping**: AC-6, AC-6(1), AC-6(2), AC-6(5)
**CMMC Level**: 2
**Practice**: AC.L2-3.1.5

**Implementation Description**:
Least privilege is enforced through granular IAM policies, service account constraints, and regular access reviews. Default permissions are deny-all; specific grants are made based on job function. Privileged operations require justification and are subject to audit logging.

**Implementing Tools**:
1. **GCP Cloud IAM** (Primary)
   - Custom roles with minimal permissions
   - Conditional access policies
   - Just-in-time access via PAM integration

2. **osquery** (Supporting)
   - Continuous privilege monitoring
   - Unauthorized privilege escalation detection
   - Query-based access audits

3. **Gitea** (Supporting)
   - Repository-level permissions
   - Organization role hierarchy

**Technical Configuration**:
```hcl
# Custom IAM role for CI/CD runner
resource "google_project_iam_custom_role" "cicd_runner" {
  role_id     = "cicdRunner"
  title       = "CI/CD Pipeline Runner"
  description = "Minimal permissions for CI/CD automation"

  permissions = [
    "storage.objects.create",
    "storage.objects.get",
    "storage.buckets.get",
    "logging.logEntries.create",
    "monitoring.timeSeries.create"
  ]
}

# Service account with least privilege
resource "google_service_account" "gitea_runner" {
  account_id   = "gitea-cicd-runner"
  display_name = "Gitea CI/CD Runner"
  description  = "Service account for pipeline execution - least privilege"
}

resource "google_project_iam_member" "runner_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.cicd_runner.id
  member  = "serviceAccount:${google_service_account.gitea_runner.email}"

  condition {
    title       = "Time-based access"
    description = "Only during business hours"
    expression  = "request.time.getHours('America/New_York') >= 6 && request.time.getHours('America/New_York') <= 20"
  }
}
```

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/access-control/ac-3.1.5/
- **Collection Frequency**: Weekly access reviews + Real-time audit logs
- **Artifacts**:
  - IAM policy exports (JSON from `gcloud projects get-iam-policy`)
  - Service account permission inventory
  - Quarterly access review reports
  - Privilege escalation detection logs (osquery)

**Collection Procedure**:
```bash
# Weekly IAM policy audit
gcloud projects get-iam-policy ${PROJECT_ID} --format=json | \
  jq '{
    bindings: [.bindings[] | {
      role: .role,
      members: .members,
      condition: .condition
    }]
  }' | tee /tmp/iam_policy.json

# Analyze for overprivileged accounts
python3 analyze_iam_privileges.py /tmp/iam_policy.json \
  --output /tmp/overprivilege_report.csv

# Hash and store
sha256sum /tmp/iam_policy.json > /tmp/iam_policy.json.sha256
gsutil cp /tmp/iam_policy.json \
  gs://compliance-evidence-store/access-control/ac-3.1.5/$(date +%Y%m%d)/
```

**Testing Procedure**:
1. Verify service accounts cannot assume admin roles
2. Test conditional access policies (time-based, IP-based)
3. Attempt privilege escalation (expect: denied + alert generated)
4. Review osquery results for unauthorized sudo usage

**Responsible Party**: Identity and Access Management Team
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-03
**Next Review**: 2025-11-03

---

### AC.L2-3.1.12 - Monitor and control remote access sessions

**NIST SP 800-171 Rev. 2 Citation**: §3.1.12
**NIST SP 800-53 Rev. 5 Mapping**: AC-17, AC-17(1), AC-17(2)
**CMMC Level**: 2
**Practice**: AC.L2-3.1.12

**Implementation Description**:
All remote access to the Gitea platform is logged, monitored, and controlled through encrypted sessions. Access is restricted to authorized endpoints, requires multi-factor authentication, and is subject to session timeout policies.

**Implementing Tools**:
1. **Cloud Logging** (Primary)
   - Centralized session logging
   - Real-time log analysis
   - Long-term retention (3 years)

2. **Grafana** (Supporting)
   - Session monitoring dashboards
   - Active session visualization
   - Connection anomaly detection

3. **Prometheus** (Supporting)
   - Connection metrics collection
   - Failed login attempt tracking
   - Session duration monitoring

**Technical Configuration**:
```yaml
# Cloud Logging sink configuration
resource "google_logging_project_sink" "remote_access_logs" {
  name        = "remote-access-audit-sink"
  destination = "storage.googleapis.com/compliance-audit-logs"

  filter = <<-EOT
    resource.type="gce_instance" AND
    (protoPayload.methodName="v1.compute.instances.start" OR
     protoPayload.methodName="v1.compute.instances.setMetadata" OR
     logName=~"sshd")
  EOT

  unique_writer_identity = true
}

# Grafana dashboard configuration
dashboard:
  title: "Remote Access Monitoring"
  panels:
    - title: "Active SSH Sessions"
      datasource: Prometheus
      targets:
        - expr: count(node_user_sessions{type="ssh"})

    - title: "Failed Login Attempts"
      datasource: Loki
      targets:
        - expr: '{job="auth"} |= "Failed password"'

    - title: "Session Duration"
      datasource: Prometheus
      targets:
        - expr: histogram_quantile(0.95, session_duration_seconds_bucket)
```

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/access-control/ac-3.1.12/
- **Collection Frequency**: Real-time + Daily summaries
- **Artifacts**:
  - SSH connection logs with source IP, username, timestamp
  - Web session logs (authenticated requests)
  - VPN connection records (if applicable)
  - Failed access attempt logs

**Testing Procedure**:
1. Establish remote session and verify logging in Cloud Logging
2. Test session timeout (30 minutes inactivity)
3. Verify failed login attempts are logged and alerted
4. Confirm MFA is required for remote admin access

**Responsible Party**: Security Operations Center (SOC)
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-04
**Next Review**: 2025-11-04

---

## AUDIT AND ACCOUNTABILITY (AU) - NIST SP 800-171 §3.3

### AU.L2-3.3.1 - Create and retain system audit records

**NIST SP 800-171 Rev. 2 Citation**: §3.3.1
**NIST SP 800-53 Rev. 5 Mapping**: AU-2, AU-3, AU-11, AU-12
**CMMC Level**: 2
**Practice**: AU.L2-3.3.1

**Implementation Description**:
Comprehensive audit logging is implemented across all components of the Gitea DevSecOps platform. Logs capture user actions, system events, security-relevant activities, and administrative functions. All logs are centralized in Cloud Logging with retention policies meeting compliance requirements (3 years minimum, 7 years for financial/regulatory records).

**Implementing Tools**:
1. **Cloud Logging** (Primary)
   - Centralized log aggregation
   - Structured logging with JSON format
   - Immutable log storage

2. **Loki** (Supporting)
   - Application log aggregation
   - Label-based log indexing
   - Integration with Grafana

3. **Gitea** (Native Logging)
   - Application audit trail
   - Repository activity logs
   - Administrative action logs

4. **n8n** (Workflow Logs)
   - Automation execution history
   - Workflow state changes
   - Error and exception logs

**Technical Configuration**:
```yaml
# Gitea logging configuration
[log]
MODE = file,conn
LEVEL = Info
ROOT_PATH = /var/log/gitea
FILE_NAME = gitea.log
ROTATE = true
MAX_DAYS = 7
ENABLE_SSH_LOG = true

[log.conn]
RECONNECT = true
PROTOCOL = tcp
ADDR = log-aggregator.internal:514

# Cloud Logging retention policy
resource "google_logging_project_bucket_config" "audit_logs" {
  project        = var.project_id
  location       = "global"
  bucket_id      = "audit-logs-retention"
  retention_days = 1095  # 3 years
  locked         = true  # Immutable after creation
}

# Loki configuration
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 3
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: gcs
      schema: v11
      index:
        prefix: loki_index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
  gcs:
    bucket_name: gitea-logs-archive
```

**Audit Event Categories**:
1. **Authentication Events**
   - User login/logout
   - Failed authentication attempts
   - MFA verification
   - Session creation/termination

2. **Authorization Events**
   - Permission grants/revocations
   - Role assignments
   - Access denials

3. **Resource Access**
   - Repository clones/pulls
   - File access in CUI repositories
   - API calls

4. **Administrative Actions**
   - User account creation/modification/deletion
   - System configuration changes
   - Security policy updates

5. **Security Events**
   - Vulnerability detections
   - Policy violations
   - Incident response actions

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/audit-accountability/au-3.3.1/
- **Collection Frequency**: Real-time ingestion + Daily exports
- **Artifacts**:
  - Daily log exports (compressed JSON)
  - Log integrity hashes (SHA-256)
  - Retention verification reports
  - Log completeness checks

**Collection Procedure**:
```bash
# Daily audit log export
gcloud logging read \
  'timestamp >= "$(date -u -d '1 day ago' --iso-8601=seconds)"' \
  --format=json \
  --project=${PROJECT_ID} | \
  gzip > /tmp/audit_logs_$(date +%Y%m%d).json.gz

# Generate hash for integrity
sha256sum /tmp/audit_logs_$(date +%Y%m%d).json.gz > \
  /tmp/audit_logs_$(date +%Y%m%d).json.gz.sha256

# Store with immutable flag
gsutil -h "x-goog-if-generation-match:0" \
  cp /tmp/audit_logs_$(date +%Y%m%d).json.gz \
  gs://compliance-evidence-store/audit-accountability/au-3.3.1/$(date +%Y)/$(date +%m)/

# Verify retention policy
gsutil retention get gs://compliance-evidence-store/
```

**Testing Procedure**:
1. Perform test action (e.g., login) and verify log entry created within 1 second
2. Verify log includes all required fields (timestamp, user, action, result)
3. Confirm logs are immutable (attempt modification, expect: failure)
4. Test log export and hash verification
5. Verify retention policy prevents premature deletion

**Responsible Party**: Security Logging Team
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-05
**Next Review**: 2025-11-05

---

### AU.L2-3.3.2 - Ensure actions can be traced to responsible users

**NIST SP 800-171 Rev. 2 Citation**: §3.3.2
**NIST SP 800-53 Rev. 5 Mapping**: AU-3, AC-2(4), IA-2(1)
**CMMC Level**: 2
**Practice**: AU.L2-3.3.2

**Implementation Description**:
All system activities are attributed to individual user identities through unique user IDs. Service accounts and system processes are logged separately with clear attribution. Shared accounts are prohibited. All audit records include user identity, timestamp, action performed, and outcome.

**Implementing Tools**:
1. **Cloud IAM** (Primary)
   - Unique identity per user/service account
   - Identity propagation through API calls
   - Audit log enrichment with principal information

2. **Gitea** (Supporting)
   - Per-user Git commits (author/committer fields)
   - Web action attribution
   - API token ownership tracking

3. **Wazuh** (Supporting)
   - File integrity monitoring with user attribution
   - Command execution tracking
   - Privileged action auditing

**Technical Configuration**:
```yaml
# Gitea user identity enforcement
[repository]
ENABLE_PUSH_CREATE_USER = false
ENABLE_PUSH_CREATE_ORG = false
DEFAULT_PRIVATE = public
FORCE_PRIVATE = false
# Require GPG signing for commits
ENABLE_SIGNING = true
SIGNING_KEY = default
SIGNING_NAME = Gitea
SIGNING_EMAIL = gitea@example.com

# Cloud IAM audit log configuration
resource "google_project_iam_audit_config" "audit_config" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Wazuh ruleset for user attribution
<group name="user_attribution">
  <rule id="100001" level="3">
    <if_sid>5710</if_sid>
    <description>User command execution detected</description>
    <options>no_log</options>
  </rule>

  <rule id="100002" level="10">
    <if_sid>100001</if_sid>
    <field name="user">^(root|admin)</field>
    <description>Privileged user command: $(user) executed $(command)</description>
  </rule>
</group>
```

**Audit Record Fields**:
All audit records contain:
- **Principal**: User email or service account identifier
- **Timestamp**: UTC ISO 8601 format
- **Action**: API method or operation performed
- **Resource**: Target resource (repository, file, configuration)
- **Result**: Success/failure status code
- **Source IP**: Originating IP address
- **User Agent**: Client information
- **Session ID**: Session correlation identifier

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/audit-accountability/au-3.3.2/
- **Collection Frequency**: Real-time + Weekly attribution reports
- **Artifacts**:
  - User action attribution matrix
  - Service account activity logs
  - Shared account detection reports (should be zero)
  - Non-repudiation evidence (signed commits)

**Testing Procedure**:
1. Perform action as User A, verify logs show User A (not generic account)
2. Review logs for presence of all required attribution fields
3. Scan for shared account usage (expect: zero instances)
4. Verify GPG commit signatures link to individual developers
5. Test service account attribution in automated workflows

**Responsible Party**: Audit and Compliance Team
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-04
**Next Review**: 2025-11-04

---

### AU.L2-3.3.4 - Alert in the event of an audit logging process failure

**NIST SP 800-171 Rev. 2 Citation**: §3.3.4
**NIST SP 800-53 Rev. 5 Mapping**: AU-5, AU-5(1), AU-5(2)
**CMMC Level**: 2
**Practice**: AU.L2-3.3.4

**Implementation Description**:
Real-time monitoring detects audit logging failures (disk full, service unavailable, connection lost) and triggers automated alerts to the security operations team. Critical systems transition to fail-secure mode (block operations) if logging cannot be guaranteed.

**Implementing Tools**:
1. **AlertManager** (Primary)
   - Alert aggregation and routing
   - Escalation policies
   - Integration with PagerDuty, Google Chat

2. **Prometheus** (Supporting)
   - Logging system health metrics
   - Disk usage monitoring
   - Log ingestion rate tracking

3. **n8n** (Supporting)
   - Alert workflow automation
   - Remediation playbook execution
   - Incident ticket creation

**Technical Configuration**:
```yaml
# Prometheus alert rules for logging failures
groups:
  - name: audit_logging_alerts
    interval: 30s
    rules:
      - alert: LoggingServiceDown
        expr: up{job="cloud-logging-agent"} == 0
        for: 2m
        labels:
          severity: critical
          compliance: AU.L2-3.3.4
        annotations:
          summary: "Audit logging service is down"
          description: "Cloud Logging agent on {{ $labels.instance }} has been down for 2 minutes"
          remediation: "Execute logging-restore-playbook.yml"

      - alert: LogDiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/var/log"} / node_filesystem_size_bytes{mountpoint="/var/log"}) < 0.15
        for: 5m
        labels:
          severity: warning
          compliance: AU.L2-3.3.4
        annotations:
          summary: "Audit log disk space low"
          description: "Log partition on {{ $labels.instance }} is {{ $value | humanizePercentage }} full"

      - alert: LogIngestionStalled
        expr: rate(log_entries_ingested_total[5m]) == 0
        for: 10m
        labels:
          severity: critical
          compliance: AU.L2-3.3.4
        annotations:
          summary: "Log ingestion has stalled"
          description: "No logs received in last 10 minutes - potential collection failure"

# AlertManager routing configuration
route:
  group_by: ['alertname', 'compliance']
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'security-team'

  routes:
    - match:
        severity: critical
        compliance: AU.L2-3.3.4
      receiver: 'pagerduty-critical'
      continue: true

    - match:
        severity: critical
      receiver: 'google-chat-security'

receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '<pagerduty_key>'
        severity: 'critical'
        description: '{{ .CommonAnnotations.summary }}'

  - name: 'google-chat-security'
    webhook_configs:
      - url: 'https://chat.googleapis.com/v1/spaces/SPACE_ID/messages?key=KEY'

# n8n automated remediation workflow
{
  "nodes": [
    {
      "name": "Alert Webhook",
      "type": "n8n-nodes-base.webhook",
      "webhookId": "audit-logging-alert"
    },
    {
      "name": "Create Incident",
      "type": "n8n-nodes-base.jira",
      "parameters": {
        "operation": "create",
        "issueType": "Incident",
        "summary": "Audit Logging Failure: {{$json.alert.annotations.summary}}",
        "priority": "Critical"
      }
    },
    {
      "name": "Execute Remediation",
      "type": "n8n-nodes-base.ansible",
      "parameters": {
        "playbook": "logging-restore-playbook.yml"
      }
    }
  ]
}
```

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/audit-accountability/au-3.3.4/
- **Collection Frequency**: Real-time alerts + Monthly test reports
- **Artifacts**:
  - Alert firing history (AlertManager exports)
  - Logging failure incident tickets
  - Remediation playbook execution logs
  - Monthly alert testing results

**Testing Procedure**:
1. **Simulate logging service failure**: `systemctl stop google-fluentd`
   - Verify alert fires within 2 minutes
   - Confirm PagerDuty notification received
   - Check JIRA incident ticket created

2. **Test disk space alert**: Fill /var/log to 86% capacity
   - Verify warning alert fires
   - Confirm log rotation triggered

3. **Validate fail-secure behavior**: If logging unavailable, verify critical operations blocked
4. **Review alert escalation**: Confirm unacknowledged critical alerts escalate within 15 minutes

**Responsible Party**: Security Operations Center (SOC)
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-01
**Next Review**: 2025-11-01

---

## CONFIGURATION MANAGEMENT (CM) - NIST SP 800-171 §3.4

### CM.L2-3.4.1 - Establish and maintain baseline configurations

**NIST SP 800-171 Rev. 2 Citation**: §3.4.1
**NIST SP 800-53 Rev. 5 Mapping**: CM-2, CM-2(2), CM-2(3), CM-6
**CMMC Level**: 2
**Practice**: CM.L2-3.4.1

**Implementation Description**:
Baseline configurations are established for all system components using Infrastructure as Code (IaC) with Terraform. Configurations are version-controlled in Git, reviewed through pull requests, and deployed through automated pipelines. Golden images are built with Packer and hardened according to CIS benchmarks.

**Implementing Tools**:
1. **Terraform** (Primary)
   - Infrastructure baseline definitions
   - State management
   - Configuration drift detection

2. **Packer** (Supporting)
   - Golden image creation
   - Immutable infrastructure
   - Hardened base images

3. **Ansible** (Supporting)
   - Configuration management
   - Compliance remediation
   - Baseline enforcement

4. **Gitea** (Version Control)
   - Configuration repository
   - Change tracking
   - Review workflows

**Technical Configuration**:
```hcl
# Terraform baseline configuration structure
module "baseline_compute" {
  source = "./modules/compute-baseline"

  # CIS Level 1 hardening
  enable_secure_boot        = true
  enable_vtpm              = true
  enable_integrity_monitoring = true

  # Network baseline
  enable_ip_forwarding     = false
  enable_serial_port       = false

  # Logging baseline
  enable_guest_attributes  = false
  metadata = {
    enable-oslogin         = "TRUE"
    enable-oslogin-2fa     = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  # Tagging for compliance
  labels = {
    baseline_version = "v2.1.0"
    cis_benchmark    = "level-1"
    compliance_scope = "cmmc-level-2"
    last_updated     = "2025-10-01"
  }
}

# Packer template for baseline image
source "googlecompute" "baseline_ubuntu" {
  project_id   = var.project_id
  source_image_family = "ubuntu-2204-lts"
  zone         = "us-central1-a"
  image_name   = "baseline-ubuntu-2204-{{timestamp}}"

  image_labels = {
    baseline_version = "v2.1.0"
    cis_level       = "1"
    hardened        = "true"
  }

  ssh_username = "packer"
}

build {
  sources = ["source.googlecompute.baseline_ubuntu"]

  provisioner "ansible" {
    playbook_file = "./ansible/hardening-playbook.yml"
    extra_arguments = [
      "--extra-vars",
      "cis_level=1 stig_cat=2"
    ]
  }

  provisioner "shell" {
    script = "./scripts/baseline-validation.sh"
  }
}
```

**Baseline Configuration Inventory**:
| Component | Baseline Standard | Version | Last Updated | Validation Frequency |
|-----------|------------------|---------|--------------|---------------------|
| Compute Instances | CIS Ubuntu 22.04 L1 | v1.1.0 | 2025-09-15 | Weekly |
| Container Images | CIS Docker Benchmark | v1.6.0 | 2025-09-20 | Daily |
| Kubernetes | CIS Kubernetes V1.27 | v1.8.0 | 2025-09-10 | Weekly |
| Network Config | GCP Best Practices | v2.0 | 2025-09-01 | Monthly |
| Database | PostgreSQL Secure Config | v14.0 | 2025-08-25 | Weekly |

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/configuration-mgmt/cm-3.4.1/
- **Collection Frequency**: On-change (git commits) + Weekly snapshots
- **Artifacts**:
  - Terraform state files (encrypted)
  - Baseline configuration files (YAML/HCL)
  - Packer build logs and image manifests
  - CIS-CAT compliance scan results
  - Configuration drift reports

**Collection Procedure**:
```bash
# Export current Terraform state as baseline evidence
cd /terraform/gitea-platform
terraform state pull | \
  jq '{
    serial: .serial,
    terraform_version: .terraform_version,
    resources: [.resources[] | {
      type: .type,
      name: .name,
      provider: .provider,
      instances: .instances
    }]
  }' > /tmp/baseline_state_$(date +%Y%m%d).json

# Generate hash
sha256sum /tmp/baseline_state_$(date +%Y%m%d).json > \
  /tmp/baseline_state_$(date +%Y%m%d).json.sha256

# Store evidence
gsutil cp /tmp/baseline_state_$(date +%Y%m%d).json* \
  gs://compliance-evidence-store/configuration-mgmt/cm-3.4.1/$(date +%Y%m)/

# Run CIS-CAT baseline validation
sudo /opt/cis-cat/Assessor-CLI.sh \
  -b /opt/cis-cat/benchmarks/ \
  -html -csv -o /tmp/cis-report-$(date +%Y%m%d)

# Upload CIS results
gsutil cp /tmp/cis-report-$(date +%Y%m%d)* \
  gs://compliance-evidence-store/configuration-mgmt/cm-3.4.1/cis-scans/
```

**Testing Procedure**:
1. Deploy new instance from baseline image
2. Run CIS-CAT assessment (expect: >95% compliance)
3. Verify configuration matches documented baseline
4. Test configuration drift detection: Manually modify setting, verify alert within 1 hour
5. Validate rollback capability: Revert to previous baseline version

**Responsible Party**: Platform Engineering
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-02
**Next Review**: 2025-11-02

---

### CM.L2-3.4.3 - Track, review, approve, and audit changes to systems

**NIST SP 800-171 Rev. 2 Citation**: §3.4.3
**NIST SP 800-53 Rev. 5 Mapping**: CM-3, CM-3(2), CM-5, CM-9
**CMMC Level**: 2
**Practice**: CM.L2-3.4.3

**Implementation Description**:
All system changes follow a formal change management process enforced through GitOps workflows. Changes are proposed via pull requests, reviewed for security and compliance impact, approved by authorized personnel, tested in staging, and audited post-deployment. Atlantis provides automated Terraform plan/apply with approval gates.

**Implementing Tools**:
1. **Gitea** (Primary)
   - Pull request workflow
   - Code review and approval
   - Merge controls

2. **Atlantis** (Primary)
   - Terraform GitOps automation
   - Plan review before apply
   - Apply approval requirements

3. **Terragrunt** (Supporting)
   - Multi-environment orchestration
   - Dependency management
   - DRY configuration

4. **n8n** (Supporting)
   - Change notification workflows
   - Approval request automation
   - Post-deployment validation

**Technical Configuration**:
```yaml
# Atlantis server configuration
repos:
  - id: github.com/org/terraform-infrastructure
    allowed_overrides: [workflow]
    allow_custom_workflows: false

    workflow: terraform-change-mgmt
    apply_requirements: [approved, mergeable]

    pre_workflow_hooks:
      - run: terraform fmt -check
      - run: tflint
      - run: checkov -d .

    post_workflow_hooks:
      - run: |
          echo "Change applied: $PULL_NUM by $USER_NAME"
          curl -X POST $AUDIT_WEBHOOK_URL \
            -d "{\"change_id\": \"$PULL_NUM\", \"approver\": \"$USER_NAME\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

workflows:
  terraform-change-mgmt:
    plan:
      steps:
        - init
        - plan:
            extra_args: ["-out=plan.tfplan"]
        - run: terraform show -json plan.tfplan > plan.json
        - run: infracost breakdown --path plan.json

    apply:
      steps:
        - run: |
            # Require explicit approval comment
            if ! grep -q "approved by security" <<< "$COMMENT"; then
              echo "ERROR: Security approval required"
              exit 1
            fi
        - apply

# Gitea branch protection for infrastructure repo
resource "gitea_repository" "infrastructure" {
  name        = "terraform-infrastructure"
  description = "Infrastructure as Code - Baseline Configurations"
  private     = true

  # Branch protection for main
  protected_branch {
    branch_name = "main"

    enable_push                     = false
    enable_merge_whitelist          = true
    merge_whitelist_usernames       = ["atlantis-bot"]

    required_approvals              = 2
    enable_approvals_whitelist      = true
    approvals_whitelist_usernames   = ["infra-lead", "security-lead"]

    dismiss_stale_approvals         = true
    require_signed_commits          = true

    enable_status_check             = true
    status_check_contexts           = [
      "atlantis/plan",
      "security/checkov",
      "security/tfsec",
      "cost/infracost"
    ]
  }
}
```

**Change Management Workflow**:
1. Developer creates branch: `git checkout -b feature/add-monitoring`
2. Makes infrastructure changes, commits with signed commit
3. Opens pull request in Gitea
4. Atlantis automatically runs `terraform plan` on PR
5. Security review: Checkov, tfsec, Terrascan scans run
6. Cost analysis: Infracost generates cost impact report
7. Required approvals: Infrastructure Lead + Security Lead review and approve
8. Atlantis comment trigger: Developer comments `atlantis apply` after approvals
9. Atlantis applies changes with audit logging
10. Post-deployment: n8n validates deployment, sends notifications

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/configuration-mgmt/cm-3.4.3/
- **Collection Frequency**: Real-time (per change) + Monthly summaries
- **Artifacts**:
  - Pull request metadata (JSON export)
  - Atlantis plan/apply logs
  - Approval chain evidence (reviewer names, timestamps)
  - Security scan results pre-merge
  - Post-deployment validation results
  - Change failure/rollback logs

**Collection Procedure**:
```bash
# Export change management evidence for audit period
START_DATE="2025-09-01"
END_DATE="2025-09-30"

# Pull request data from Gitea API
curl -H "Authorization: token ${GITEA_TOKEN}" \
  "https://gitea.internal/api/v1/repos/org/terraform-infrastructure/pulls?state=closed&since=${START_DATE}&before=${END_DATE}" | \
  jq '[.[] | {
    number: .number,
    title: .title,
    author: .user.username,
    created: .created_at,
    merged: .merged_at,
    approvals: [.requested_reviewers[].username],
    status_checks: .labels
  }]' > /tmp/changes_${START_DATE}_${END_DATE}.json

# Atlantis audit logs
gsutil cat gs://atlantis-audit-logs/${START_DATE}_${END_DATE}/* | \
  jq -s '.' > /tmp/atlantis_audit_${START_DATE}_${END_DATE}.json

# Generate change summary report
python3 generate_change_report.py \
  --pull-requests /tmp/changes_${START_DATE}_${END_DATE}.json \
  --atlantis-logs /tmp/atlantis_audit_${START_DATE}_${END_DATE}.json \
  --output /tmp/change_management_report_${START_DATE}_${END_DATE}.pdf

# Hash and store
sha256sum /tmp/change_management_report_${START_DATE}_${END_DATE}.pdf > \
  /tmp/change_management_report_${START_DATE}_${END_DATE}.pdf.sha256

gsutil cp /tmp/change_management_report_${START_DATE}_${END_DATE}.pdf* \
  gs://compliance-evidence-store/configuration-mgmt/cm-3.4.3/$(date +%Y%m)/
```

**Testing Procedure**:
1. **Unapproved Change Test**: Attempt to merge PR without required approvals (expect: blocked)
2. **Failed Security Scan Test**: Introduce security violation, verify PR blocked until remediated
3. **Emergency Change Test**: Follow expedited approval process, verify enhanced logging
4. **Rollback Test**: Apply change, verify ability to revert via `atlantis apply` on revert PR
5. **Audit Trail Test**: Review complete change history, verify all approvals and timestamps present

**Responsible Party**: Infrastructure Engineering + Security Review Board
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-03
**Next Review**: 2025-11-03

---

## IDENTIFICATION AND AUTHENTICATION (IA) - NIST SP 800-171 §3.5

### IA.L2-3.5.3 - Use multifactor authentication for local and network access

**NIST SP 800-171 Rev. 2 Citation**: §3.5.3
**NIST SP 800-53 Rev. 5 Mapping**: IA-2(1), IA-2(2), IA-2(8), IA-2(12)
**CMMC Level**: 2
**Practice**: IA.L2-3.5.3

**Implementation Description**:
Multifactor authentication (MFA) is required for all user access to the Gitea platform and GCP resources. MFA combines knowledge factor (password) with possession factor (TOTP app, hardware token, or push notification). Administrative and privileged access requires hardware security keys (FIDO2/WebAuthn).

**Implementing Tools**:
1. **Gitea** (Primary)
   - Built-in TOTP/U2F support
   - OAuth2 integration with enterprise IdP
   - Session management with MFA verification

2. **GCP Cloud IAM** (Supporting)
   - Enforce 2-Step Verification for all users
   - Security key requirement for privileged access
   - Context-aware access policies

3. **Cloud Identity** (Supporting)
   - Centralized identity management
   - MFA policy enforcement
   - Device trust integration

**Technical Configuration**:
```yaml
# Gitea MFA configuration (app.ini)
[service]
REQUIRE_EXTERNAL_REGISTRATION_PASSWORD = true
ENABLE_CAPTCHA = true

[security]
# Enforce MFA for all users after 7 days
MFA_ENROLLMENT_GRACE_PERIOD = 168  # hours

[auth]
REQUIRE_SIGNIN_VIEW = true

# OAuth2 configuration with MFA-enabled IdP
[auth.oauth2]
ENABLED = true
CLIENT_ID = ${OAUTH_CLIENT_ID}
CLIENT_SECRET = ${OAUTH_CLIENT_SECRET}
AUTO_DISCOVER_URL = https://accounts.google.com/.well-known/openid-configuration
SCOPES = openid email profile

# GCP Organization Policy - Enforce MFA
resource "google_organization_policy" "enforce_mfa" {
  org_id     = var.organization_id
  constraint = "iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      values = ["C0xxxxxxx"]  # Cloud Identity customer ID
    }
  }
}

# Require 2SV for all users
resource "google_cloud_identity_group_membership" "mfa_required" {
  group    = google_cloud_identity_group.all_users.id

  preferred_member_key {
    id = var.user_email
  }

  roles {
    name = "MEMBER"
    restrictions {
      require_2sv = true
    }
  }
}

# Conditional access policy - require security key for privileged access
resource "google_access_context_manager_access_level" "privileged_access" {
  parent = "accessPolicies/${var.access_policy_id}"
  name   = "privileged_mfa_access_level"
  title  = "Privileged MFA Access Level"

  basic {
    conditions {
      device_policy {
        require_screenlock       = true
        require_admin_approval   = true
        require_corp_owned       = true
      }

      required_access_levels = [
        google_access_context_manager_access_level.hardware_key.id
      ]
    }
  }
}
```

**MFA Enforcement Matrix**:
| Access Type | User Category | MFA Requirement | Acceptable Methods | Grace Period |
|-------------|---------------|-----------------|-------------------|--------------|
| Gitea Web UI | All Users | Required | TOTP, WebAuthn | 7 days |
| Gitea API | Service Accounts | API Key + Client Cert | mTLS | N/A |
| GCP Console | Regular Users | Required | TOTP, Push, SMS | Immediate |
| GCP Console | Privileged Users | Required | Hardware Key (FIDO2) | Immediate |
| SSH to Compute | System Admins | Required | SSH Key + OTP | Immediate |
| VPN Access | Remote Workers | Required | TOTP + Device Certificate | Immediate |

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/identification-auth/ia-3.5.3/
- **Collection Frequency**: Daily enrollment reports + Real-time auth logs
- **Artifacts**:
  - MFA enrollment status by user (CSV)
  - Authentication method breakdown (TOTP vs Hardware Key)
  - Failed MFA attempt logs
  - MFA bypass exception tracking (should be zero)
  - 2SV compliance reports from Google Workspace Admin

**Collection Procedure**:
```bash
# Export Gitea MFA enrollment status
curl -H "Authorization: token ${GITEA_TOKEN}" \
  https://gitea.internal/api/v1/admin/users | \
  jq -r '["Username","Email","MFA_Enabled","MFA_Type","Last_Login"],
         (.[] | [.username, .email, .is_2fa_enabled, .twofa_type // "none", .last_login]) |
         @csv' > /tmp/gitea_mfa_enrollment_$(date +%Y%m%d).csv

# GCP 2SV compliance report
gcloud identity groups memberships list \
  --group-email=all-users@example.com \
  --format="csv(preferredMemberKey.id,roles.name,roles.restrictions.require_2sv)" \
  > /tmp/gcp_2sv_status_$(date +%Y%m%d).csv

# Analyze for non-compliant users
python3 << 'EOF'
import pandas as pd
from datetime import datetime

gitea_df = pd.read_csv('/tmp/gitea_mfa_enrollment_$(date +%Y%m%d).csv')
non_compliant = gitea_df[gitea_df['MFA_Enabled'] == False]

if len(non_compliant) > 0:
    print(f"WARNING: {len(non_compliant)} users without MFA:")
    print(non_compliant.to_string())

    # Generate remediation tickets
    for _, user in non_compliant.iterrows():
        print(f"JIRA ticket needed for: {user['Email']}")
else:
    print("All users have MFA enabled - COMPLIANT")
EOF

# Hash and store
sha256sum /tmp/gitea_mfa_enrollment_$(date +%Y%m%d).csv > \
  /tmp/gitea_mfa_enrollment_$(date +%Y%m%d).csv.sha256

gsutil cp /tmp/gitea_mfa_enrollment_$(date +%Y%m%d).csv* \
  gs://compliance-evidence-store/identification-auth/ia-3.5.3/$(date +%Y%m)/
```

**Testing Procedure**:
1. **User Enrollment Test**:
   - Create new user account
   - Attempt login without MFA (expect: enrollment prompt)
   - Complete TOTP enrollment
   - Verify successful login with MFA

2. **MFA Bypass Prevention Test**:
   - Attempt to disable user's MFA as admin (expect: blocked or requires security approval)
   - Verify no backdoor accounts exist without MFA

3. **Privileged Access Test**:
   - Attempt GCP console login with privileged account using TOTP (expect: denied)
   - Authenticate with hardware security key (expect: success)

4. **Failed MFA Test**:
   - Enter incorrect TOTP code 5 times
   - Verify account lockout after threshold
   - Confirm alert sent to security team

5. **Session Validation Test**:
   - Login with MFA, establish session
   - Attempt privileged action, verify MFA re-challenge after timeout

**Responsible Party**: Identity and Access Management Team
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-04
**Next Review**: 2025-11-04

---

## INCIDENT RESPONSE (IR) - NIST SP 800-171 §3.6

### IR.L2-3.6.1 - Establish an operational incident-handling capability

**NIST SP 800-171 Rev. 2 Citation**: §3.6.1
**NIST SP 800-53 Rev. 5 Mapping**: IR-4, IR-4(1), IR-5, IR-6
**CMMC Level**: 2
**Practice**: IR.L2-3.6.1

**Implementation Description**:
A comprehensive incident response capability is established with automated detection, triage, escalation, and response workflows. Incidents are detected through security monitoring tools, automatically triaged by severity, escalated through PagerDuty integration, and managed through structured playbooks executed via n8n and Ansible.

**Implementing Tools**:
1. **Wazuh** (Primary - Detection)
   - HIDS/SIEM for security event detection
   - Rule-based alert generation
   - Integration with MITRE ATT&CK framework

2. **n8n** (Primary - Orchestration)
   - Incident response workflow automation
   - Escalation logic
   - Playbook execution

3. **Taiga** (Supporting - Tracking)
   - Incident ticket management
   - Status tracking and reporting
   - Post-incident review management

4. **Google Chat / PagerDuty** (Supporting - Notification)
   - Real-time incident notifications
   - On-call escalation
   - Team collaboration

5. **Ansible** (Supporting - Remediation)
   - Automated response playbooks
   - Containment actions
   - System isolation procedures

**Technical Configuration**:
```yaml
# Wazuh incident detection rules
<group name="incident_detection">
  <!-- High-severity security event -->
  <rule id="100100" level="12">
    <if_group>authentication_failed</if_group>
    <description>Multiple failed authentication attempts detected</description>
    <options>no_log</options>
    <same_source_ip />
    <different_user />
    <timeframe>120</timeframe>
    <frequency>5</frequency>
    <mitre>
      <id>T1110</id>
      <tactic>Credential Access</tactic>
      <technique>Brute Force</technique>
    </mitre>
  </rule>

  <!-- Privilege escalation attempt -->
  <rule id="100101" level="15">
    <if_sid>5401</if_sid>
    <match>sudo: .+ : user NOT in sudoers</match>
    <description>Unauthorized privilege escalation attempt</description>
    <mitre>
      <id>T1548</id>
      <tactic>Privilege Escalation</tactic>
      <technique>Abuse Elevation Control Mechanism</technique>
    </mitre>
  </rule>

  <!-- Data exfiltration indicator -->
  <rule id="100102" level="13">
    <if_group>network</if_group>
    <match>outbound_bytes > 1000000000</match>
    <description>Potential data exfiltration - large outbound transfer</description>
    <mitre>
      <id>T1048</id>
      <tactic>Exfiltration</tactic>
      <technique>Exfiltration Over Alternative Protocol</technique>
    </mitre>
  </rule>
</group>

# n8n Incident Response Workflow
{
  "name": "Incident Response Automation",
  "nodes": [
    {
      "name": "Wazuh Alert Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "wazuh-incident",
        "responseMode": "onReceived"
      }
    },
    {
      "name": "Severity Triage",
      "type": "n8n-nodes-base.switch",
      "parameters": {
        "rules": {
          "values": [
            {
              "conditions": {
                "number": [
                  {
                    "value1": "={{$json.alert.level}}",
                    "operation": "largerEqual",
                    "value2": 12
                  }
                ]
              },
              "renameOutput": "critical"
            },
            {
              "conditions": {
                "number": [
                  {
                    "value1": "={{$json.alert.level}}",
                    "operation": "between",
                    "value2": 7,
                    "value3": 11
                  }
                ]
              },
              "renameOutput": "high"
            }
          ]
        }
      }
    },
    {
      "name": "Create JIRA Incident",
      "type": "n8n-nodes-base.jira",
      "parameters": {
        "operation": "create",
        "project": "SEC",
        "issueType": "Incident",
        "summary": "Security Incident: {{$json.alert.rule.description}}",
        "description": "MITRE Technique: {{$json.alert.rule.mitre.technique}}\\nSource: {{$json.alert.data.srcip}}\\nTimestamp: {{$json.alert.timestamp}}",
        "priority": "Critical"
      }
    },
    {
      "name": "Page On-Call",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "method": "POST",
        "url": "https://api.pagerduty.com/incidents",
        "headers": {
          "Authorization": "Token token={{$credentials.pagerDutyApiKey}}",
          "Content-Type": "application/json"
        },
        "body": {
          "incident": {
            "type": "incident",
            "title": "{{$json.alert.rule.description}}",
            "service": {
              "id": "SECURITY_SERVICE_ID",
              "type": "service_reference"
            },
            "urgency": "high",
            "incident_key": "{{$json.alert.id}}",
            "body": {
              "type": "incident_body",
              "details": "MITRE ATT&CK: {{$json.alert.rule.mitre.id}}"
            }
          }
        }
      }
    },
    {
      "name": "Execute Containment Playbook",
      "type": "n8n-nodes-base.ansible",
      "parameters": {
        "playbookId": "incident-containment.yml",
        "extraVars": {
          "incident_id": "={{$json.alert.id}}",
          "affected_host": "={{$json.alert.agent.name}}",
          "action": "isolate"
        }
      }
    },
    {
      "name": "Notify Security Team",
      "type": "n8n-nodes-base.googleChat",
      "parameters": {
        "space": "spaces/SECURITY_OPS_SPACE",
        "message": "🚨 SECURITY INCIDENT\\n*Severity:* Critical\\n*Description:* {{$json.alert.rule.description}}\\n*JIRA:* {{$node['Create JIRA Incident'].json.key}}\\n*Status:* Containment initiated"
      }
    }
  ],
  "connections": {
    "Wazuh Alert Webhook": {
      "main": [[{"node": "Severity Triage"}]]
    },
    "Severity Triage": {
      "critical": [[
        {"node": "Create JIRA Incident"},
        {"node": "Page On-Call"},
        {"node": "Execute Containment Playbook"}
      ]],
      "high": [[
        {"node": "Create JIRA Incident"},
        {"node": "Notify Security Team"}
      ]]
    }
  }
}

# Ansible containment playbook
---
- name: Incident Containment Playbook
  hosts: "{{ affected_host }}"
  become: yes

  tasks:
    - name: Log incident response action
      ansible.builtin.lineinfile:
        path: /var/log/incident-response.log
        line: "{{ ansible_date_time.iso8601 }} - Incident {{ incident_id }} - Action: {{ action }}"
        create: yes

    - name: Isolate host from network (if action=isolate)
      when: action == "isolate"
      block:
        - name: Block all outbound traffic
          ansible.builtin.iptables:
            chain: OUTPUT
            policy: DROP

        - name: Allow only SSH from jumphost
          ansible.builtin.iptables:
            chain: INPUT
            protocol: tcp
            destination_port: 22
            source: "{{ jumphost_ip }}"
            jump: ACCEPT

        - name: Save iptables rules
          ansible.builtin.shell: iptables-save > /etc/iptables/rules.v4

    - name: Capture forensic snapshot
      ansible.builtin.command:
        cmd: gcloud compute disks snapshot {{ ansible_hostname }}-disk --snapshot-names=forensic-{{ incident_id }}-{{ ansible_date_time.epoch }}
      delegate_to: localhost

    - name: Notify completion
      ansible.builtin.uri:
        url: "{{ n8n_webhook_url }}"
        method: POST
        body_format: json
        body:
          incident_id: "{{ incident_id }}"
          action: "{{ action }}"
          status: "completed"
          timestamp: "{{ ansible_date_time.iso8601 }}"
```

**Incident Response Capability Components**:
1. **Detection**: Wazuh SIEM, Security Command Center, Falco runtime monitoring
2. **Triage**: Automated severity classification, MITRE ATT&CK mapping
3. **Escalation**: PagerDuty on-call notification, Security team alerting
4. **Containment**: Automated system isolation, network quarantine
5. **Investigation**: Forensic data collection, log aggregation, timeline analysis
6. **Remediation**: Playbook-driven response, vulnerability patching
7. **Recovery**: Service restoration procedures, validation testing
8. **Post-Incident**: Lessons learned, playbook updates, training

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/incident-response/ir-3.6.1/
- **Collection Frequency**: Real-time (per incident) + Quarterly tabletop exercises
- **Artifacts**:
  - Incident ticket exports (JIRA)
  - Detection alert history (Wazuh)
  - Response playbook execution logs (Ansible)
  - Escalation and notification logs (PagerDuty, Google Chat)
  - Forensic snapshots and investigation notes
  - Tabletop exercise reports

**Testing Procedure**:
1. **Simulated Incident Test** (Monthly):
   - Inject test alert into Wazuh
   - Verify n8n workflow triggers
   - Confirm JIRA ticket created
   - Validate PagerDuty notification (test service)
   - Check containment playbook dry-run

2. **Tabletop Exercise** (Quarterly):
   - Scenario: Ransomware detection on developer workstation
   - Exercise response procedures with Security, DevOps, Legal
   - Document findings and improvement opportunities
   - Update playbooks based on lessons learned

3. **Mean Time to Respond (MTTR) Validation**:
   - Measure time from detection to acknowledgment: Target <5 minutes
   - Measure time from acknowledgment to containment: Target <15 minutes
   - Track via JIRA incident timestamps

**Responsible Party**: Security Operations Center (SOC) + Incident Response Team
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-01
**Next Review**: 2025-11-01

---

## RISK ASSESSMENT (RA) - NIST SP 800-171 §3.11

### RA.L2-3.11.2 - Scan for vulnerabilities and remediate in accordance with risk

**NIST SP 800-171 Rev. 2 Citation**: §3.11.2
**NIST SP 800-53 Rev. 5 Mapping**: RA-5, RA-5(1), RA-5(2), RA-5(5), RA-5(8)
**CMMC Level**: 2
**Practice**: RA.L2-3.11.2

**Implementation Description**:
Comprehensive vulnerability scanning is performed across all layers: source code (SAST), containers (image scanning), infrastructure (IaC scanning), runtime (DAST), and cloud resources (Security Command Center). Scans run automatically on every code commit/build and on scheduled intervals. Vulnerabilities are prioritized by CVSS score, exploitability, and exposure, with defined SLAs for remediation.

**Implementing Tools**:
1. **Trivy** (Primary - Container Scanning)
   - CVE detection in container images
   - OS package vulnerabilities
   - Application dependency scanning
   - SBOM generation

2. **Grype** (Primary - Vulnerability Matching)
   - Multi-source vulnerability database
   - Language-specific package vulnerabilities
   - License compliance checking

3. **SonarQube** (Primary - SAST)
   - Code quality and security bugs
   - OWASP Top 10 detection
   - Security hotspot analysis

4. **OWASP ZAP** (Supporting - DAST)
   - Runtime application security testing
   - API vulnerability scanning
   - Authentication/authorization testing

5. **Security Command Center** (Supporting - Cloud Resources)
   - GCP resource misconfigurations
   - IAM vulnerabilities
   - Network exposure issues

6. **Checkov** (Supporting - IaC Scanning)
   - Terraform security violations
   - CIS benchmark compliance
   - Policy-as-code validation

**Technical Configuration**:
```yaml
# CI/CD pipeline vulnerability scanning stages
stages:
  - name: "Source Code Scan"
    tools:
      - sonarqube:
          quality_gate: "CMMC_Level_2"
          fail_on: "blocker,critical"
          coverage_threshold: 80

      - semgrep:
          config: "p/ci,p/security-audit,p/secrets"
          severity_threshold: "ERROR"

      - bandit:
          level: "MEDIUM"
          confidence: "MEDIUM"

  - name: "Container Image Scan"
    tools:
      - trivy:
          severity: "HIGH,CRITICAL"
          scanners: "vuln,secret,config"
          exit_code: 1
          timeout: 10m

      - grype:
          fail_on: "high"
          output: "json,sarif"
          scope: "all-layers"

  - name: "IaC Security Scan"
    tools:
      - checkov:
          framework: "terraform,kubernetes"
          soft_fail: false
          check: "CKV_GCP_*,CKV_K8S_*"

      - tfsec:
          minimum_severity: "MEDIUM"
          exclude_downloaded_modules: false

  - name: "Dynamic Application Scan"
    trigger: "on_merge_to_staging"
    tools:
      - zap:
          target: "https://staging.gitea.internal"
          scan_type: "full"
          alert_threshold: "MEDIUM"

# Trivy configuration
---
vulnerability:
  type:
    - os
    - library

severity:
    - CRITICAL
    - HIGH
    - MEDIUM

ignore-unfixed: false

secret:
  config-path: ".trivy/secret.yaml"

# Remediation SLA matrix
remediation_slas:
  critical:
    description: "CVSS 9.0-10.0 or active exploitation"
    sla: "24 hours"
    escalation: "Immediate - Security Lead + CTO"

  high:
    description: "CVSS 7.0-8.9"
    sla: "7 days"
    escalation: "Security Team + Product Owner"

  medium:
    description: "CVSS 4.0-6.9"
    sla: "30 days"
    escalation: "Engineering Team"

  low:
    description: "CVSS 0.1-3.9"
    sla: "90 days or next release"
    escalation: "Backlog prioritization"
```

**Vulnerability Scanning Schedule**:
| Scan Type | Frequency | Scope | Tool(s) | Auto-Remediation |
|-----------|-----------|-------|---------|------------------|
| Source Code (SAST) | Every commit | All repositories | SonarQube, Semgrep | No - requires developer fix |
| Container Images | Every build + Daily scan of registry | All container images | Trivy, Grype | Automated rebuild if base image updated |
| IaC Configurations | Every PR + Weekly | Terraform, K8s manifests | Checkov, tfsec, Terrascan | Terraform plan blocked on violation |
| Runtime (DAST) | Weekly | Staging/production endpoints | OWASP ZAP | No - requires code fix |
| Cloud Resources | Continuous | All GCP resources | Security Command Center | Automated remediation for low-risk findings |
| Dependencies | Daily | All package manifests | Dependabot, Trivy | Automated PRs for patch updates |

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/risk-assessment/ra-3.11.2/
- **Collection Frequency**: Per-scan (real-time) + Weekly summaries
- **Artifacts**:
  - Vulnerability scan reports (JSON, SARIF, HTML)
  - SBOM exports (SPDX, CycloneDX)
  - Remediation tracking (JIRA ticket exports)
  - SLA compliance reports
  - Vulnerability trend analysis

**Collection Procedure**:
```bash
#!/bin/bash
# Daily vulnerability evidence collection

DATE=$(date +%Y%m%d)
EVIDENCE_DIR="/tmp/vuln_evidence_${DATE}"
mkdir -p "${EVIDENCE_DIR}"

# 1. Collect Trivy scan results
echo "[$(date)] Collecting Trivy scan results..."
for image in $(gcloud container images list --repository=gcr.io/${PROJECT_ID} --format="value(name)"); do
    image_name=$(basename ${image})
    trivy image --format json --output "${EVIDENCE_DIR}/trivy_${image_name}_${DATE}.json" ${image}
    trivy image --format cyclonedx --output "${EVIDENCE_DIR}/sbom_${image_name}_${DATE}.json" ${image}
done

# 2. Collect SonarQube scan results
echo "[$(date)] Collecting SonarQube findings..."
curl -u "${SONAR_TOKEN}:" \
  "https://sonar.internal/api/issues/search?componentKeys=gitea-platform&severities=BLOCKER,CRITICAL,MAJOR&statuses=OPEN&ps=500" | \
  jq '.' > "${EVIDENCE_DIR}/sonarqube_issues_${DATE}.json"

# 3. Collect Security Command Center findings
echo "[$(date)] Collecting GCP SCC findings..."
gcloud scc findings list ${ORG_ID} \
  --filter="state=ACTIVE AND category!=OPEN_FIREWALL" \
  --format=json > "${EVIDENCE_DIR}/scc_findings_${DATE}.json"

# 4. Generate vulnerability summary report
python3 << 'EOF' > "${EVIDENCE_DIR}/vuln_summary_${DATE}.json"
import json
import glob
from collections import Counter

vuln_summary = {
    "date": "${DATE}",
    "total_vulnerabilities": 0,
    "by_severity": {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0},
    "by_source": {},
    "sla_violations": []
}

# Process Trivy results
for trivy_file in glob.glob("${EVIDENCE_DIR}/trivy_*.json"):
    with open(trivy_file) as f:
        data = json.load(f)
        for result in data.get("Results", []):
            for vuln in result.get("Vulnerabilities", []):
                vuln_summary["total_vulnerabilities"] += 1
                severity = vuln.get("Severity", "UNKNOWN")
                vuln_summary["by_severity"][severity] = vuln_summary["by_severity"].get(severity, 0) + 1

print(json.dumps(vuln_summary, indent=2))
EOF

# 5. Hash all evidence files
echo "[$(date)] Generating hashes..."
cd "${EVIDENCE_DIR}"
find . -type f -exec sha256sum {} \; > checksums.sha256

# 6. Upload to GCS
echo "[$(date)] Uploading to GCS..."
gsutil -m cp -r "${EVIDENCE_DIR}" \
  gs://compliance-evidence-store/risk-assessment/ra-3.11.2/$(date +%Y)/$(date +%m)/

# 7. Cleanup
rm -rf "${EVIDENCE_DIR}"

echo "[$(date)] Vulnerability evidence collection complete"
```

**Testing Procedure**:
1. **Scan Coverage Test**:
   - Build new container image with known CVE
   - Verify Trivy detects vulnerability
   - Confirm scan blocks image promotion to production

2. **Remediation Workflow Test**:
   - Identify CRITICAL vulnerability
   - Verify JIRA ticket auto-created
   - Apply fix, rebuild image
   - Confirm vulnerability resolved in next scan

3. **SLA Compliance Test**:
   - Query vulnerabilities older than SLA threshold
   - Generate exception report
   - Escalate per policy

4. **False Positive Handling**:
   - Mark vulnerability as false positive in SonarQube
   - Verify suppression carries forward in subsequent scans
   - Document justification in compliance system

**Responsible Party**: Application Security Team + DevOps Engineering
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-03
**Next Review**: 2025-11-03

---

## SYSTEM AND COMMUNICATIONS PROTECTION (SC) - NIST SP 800-171 §3.13

### SC.L2-3.13.16 - Protect the confidentiality of CUI at rest

**NIST SP 800-171 Rev. 2 Citation**: §3.13.16
**NIST SP 800-53 Rev. 5 Mapping**: SC-28, SC-28(1), SC-28(3), SC-12, SC-13
**CMMC Level**: 2
**Practice**: SC.L2-3.13.16

**Implementation Description**:
All Controlled Unclassified Information (CUI) stored within the Gitea platform and supporting infrastructure is encrypted at rest using AES-256 encryption with customer-managed encryption keys (CMEK) via Cloud KMS. Encryption keys are rotated every 90 days, stored in HSM-backed key rings, and subject to strict access controls. All storage services (GCS, Cloud SQL, Persistent Disks) enforce encryption at rest.

**Implementing Tools**:
1. **Cloud KMS** (Primary)
   - Customer-managed encryption keys (CMEK)
   - Hardware security module (HSM) backing
   - Automated key rotation
   - Key usage audit logging

2. **GCS** (Supporting)
   - Default encryption for all objects
   - CMEK integration
   - Retention policies and versioning

3. **Cloud SQL** (Supporting)
   - Transparent data encryption (TDE)
   - CMEK for database encryption
   - Automated encrypted backups

**Technical Configuration**:
```hcl
# Cloud KMS key ring and keys for CUI encryption
resource "google_kms_key_ring" "cui_keyring" {
  name     = "cui-encryption-keyring"
  location = "us-central1"

  labels = {
    compliance = "cmmc-level-2"
    data_class = "cui"
  }
}

resource "google_kms_crypto_key" "cui_storage_key" {
  name            = "cui-storage-encryption-key"
  key_ring        = google_kms_key_ring.cui_keyring.id
  rotation_period = "7776000s"  # 90 days

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"  # Hardware Security Module backing
  }

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    compliance     = "cmmc-level-2"
    data_class     = "cui"
    rotation_days  = "90"
  }
}

# GCS bucket for CUI repositories with CMEK
resource "google_storage_bucket" "cui_repositories" {
  name          = "gitea-cui-repos-${var.project_id}"
  location      = "US"
  force_destroy = false

  uniform_bucket_level_access = true

  encryption {
    default_kms_key_name = google_kms_crypto_key.cui_storage_key.id
  }

  versioning {
    enabled = true
  }

  retention_policy {
    retention_period = 220752000  # 7 years in seconds
    is_locked        = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  labels = {
    data_classification = "cui"
    compliance_scope    = "cmmc-level-2"
    encryption          = "cmek-kms"
  }
}

# Cloud SQL database with CMEK encryption
resource "google_sql_database_instance" "gitea_db" {
  name             = "gitea-primary-db"
  database_version = "POSTGRES_14"
  region           = "us-central1"

  encryption_key_name = google_kms_crypto_key.cui_storage_key.id

  settings {
    tier              = "db-custom-4-16384"
    availability_type = "REGIONAL"  # HA configuration

    backup_configuration {
      enabled            = true
      start_time         = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 365
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.gitea_vpc.id
      require_ssl     = true
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
  }

  deletion_protection = true
}

# Compute persistent disk with encryption
resource "google_compute_disk" "gitea_data_disk" {
  name  = "gitea-data-disk"
  type  = "pd-ssd"
  zone  = "us-central1-a"
  size  = 500

  disk_encryption_key {
    kms_key_self_link = google_kms_crypto_key.cui_storage_key.id
  }

  labels = {
    data_classification = "cui"
    encryption          = "cmek"
  }
}

# IAM policy for KMS key access - least privilege
resource "google_kms_crypto_key_iam_binding" "cui_key_usage" {
  crypto_key_id = google_kms_crypto_key.cui_storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.gitea_sa.email}",
    "serviceAccount:service-${data.google_project.project.number}@compute-system.iam.gserviceaccount.com",
    "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com",
  ]
}

# Cloud KMS key usage audit logging
resource "google_project_iam_audit_config" "kms_audit" {
  project = var.project_id
  service = "cloudkms.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }

  audit_log_config {
    log_type = "ADMIN_READ"
  }
}
```

**Encryption Implementation Matrix**:
| Data Store | Encryption Method | Key Management | Algorithm | Key Rotation | Backup Encryption |
|------------|------------------|----------------|-----------|--------------|-------------------|
| GCS Buckets (CUI) | CMEK | Cloud KMS (HSM) | AES-256 | 90 days | Yes (same key) |
| Cloud SQL Database | CMEK + TDE | Cloud KMS (HSM) | AES-256 | 90 days | Yes (same key) |
| Persistent Disks | CMEK | Cloud KMS (HSM) | AES-256 | 90 days | Yes (snapshot encrypted) |
| Secrets | Envelope Encryption | Secret Manager + KMS | AES-256 | On-demand | Yes |
| Backups (cross-region) | CMEK | Cloud KMS (HSM) | AES-256 | 90 days | N/A (is backup) |

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/system-protection/sc-3.13.16/
- **Collection Frequency**: Daily encryption status + Key rotation logs
- **Artifacts**:
  - KMS key inventory with rotation status
  - Encryption verification reports (bucket/disk/db survey)
  - Key usage audit logs
  - Unencrypted resource detection scans (should be zero)
  - Key access audit trail

**Collection Procedure**:
```bash
#!/bin/bash
# Daily encryption at rest verification

DATE=$(date +%Y%m%d)
EVIDENCE_FILE="/tmp/encryption_verification_${DATE}.json"

# 1. Verify all GCS buckets use CMEK
echo "[$(date)] Verifying GCS bucket encryption..."
gcloud storage buckets list --format=json | \
  jq '[.[] | {
    name: .name,
    location: .location,
    encryption_key: .encryption.defaultKmsKeyName,
    data_classification: .labels.data_classification,
    encrypted: (if .encryption.defaultKmsKeyName != null then "YES" else "NO" end)
  }]' > /tmp/gcs_encryption.json

# 2. Verify Cloud SQL instances use CMEK
echo "[$(date)] Verifying Cloud SQL encryption..."
gcloud sql instances list --format=json | \
  jq '[.[] | {
    name: .name,
    region: .region,
    encryption_key: .diskEncryptionConfiguration.kmsKeyName,
    encrypted: (if .diskEncryptionConfiguration.kmsKeyName != null then "YES" else "NO" end)
  }]' > /tmp/sql_encryption.json

# 3. Verify compute disks use CMEK
echo "[$(date)] Verifying Compute disk encryption..."
gcloud compute disks list --format=json | \
  jq '[.[] | {
    name: .name,
    zone: .zone,
    encryption_key: .diskEncryptionKey.kmsKeyName,
    encrypted: (if .diskEncryptionKey.kmsKeyName != null then "YES" else "NO" end)
  }]' > /tmp/disk_encryption.json

# 4. Check for unencrypted resources (compliance violation)
echo "[$(date)] Checking for unencrypted CUI resources..."
UNENCRYPTED=$(jq -s '
  [.[][] | select(.encrypted == "NO" and (.data_classification == "cui" or .labels.data_classification == "cui"))]
' /tmp/gcs_encryption.json /tmp/sql_encryption.json /tmp/disk_encryption.json)

if [ "$(echo $UNENCRYPTED | jq 'length')" -gt 0 ]; then
    echo "ALERT: Unencrypted CUI resources detected!"
    echo $UNENCRYPTED | jq '.'

    # Send alert
    curl -X POST https://chat.googleapis.com/v1/spaces/COMPLIANCE_SPACE/messages \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"⚠️ COMPLIANCE VIOLATION: Unencrypted CUI resources detected. See daily report.\"}"
fi

# 5. Verify KMS key rotation
echo "[$(date)] Verifying KMS key rotation..."
gcloud kms keys list --location=us-central1 --keyring=cui-encryption-keyring --format=json | \
  jq '[.[] | {
    name: .name,
    rotation_period: .rotationPeriod,
    next_rotation: .nextRotationTime,
    primary_version: .primary.name,
    algorithm: .primary.algorithm,
    protection_level: .primary.protectionLevel
  }]' > /tmp/kms_rotation.json

# 6. Combine all evidence
jq -s '{
  date: "'${DATE}'",
  gcs_buckets: .[0],
  sql_instances: .[1],
  compute_disks: .[2],
  kms_keys: .[3],
  unencrypted_violations: '"${UNENCRYPTED}"',
  compliance_status: (if ('"${UNENCRYPTED}"' | length) == 0 then "COMPLIANT" else "NON-COMPLIANT" end)
}' /tmp/gcs_encryption.json /tmp/sql_encryption.json /tmp/disk_encryption.json /tmp/kms_rotation.json > ${EVIDENCE_FILE}

# 7. Hash and upload
sha256sum ${EVIDENCE_FILE} > ${EVIDENCE_FILE}.sha256

gsutil cp ${EVIDENCE_FILE}* \
  gs://compliance-evidence-store/system-protection/sc-3.13.16/$(date +%Y)/$(date +%m)/

echo "[$(date)] Encryption verification complete"
```

**Testing Procedure**:
1. **Encryption Verification Test**:
   ```bash
   # Verify GCS object is encrypted
   gsutil stat gs://gitea-cui-repos/test-object | grep "Encryption"
   # Expected: "Encryption: Customer-managed key"

   # Verify encryption key ID
   gsutil stat gs://gitea-cui-repos/test-object | grep "KMS key"
   # Expected: projects/PROJECT/locations/us-central1/keyRings/cui-encryption-keyring/cryptoKeys/cui-storage-encryption-key
   ```

2. **Key Rotation Test**:
   - Check current key version
   - Wait for 90-day rotation period (or trigger manual rotation)
   - Verify new key version created
   - Confirm old data still accessible with new key (envelope encryption)

3. **Access Control Test**:
   - Attempt to decrypt data without KMS permission (expect: denied)
   - Grant minimal permission to service account
   - Verify data access succeeds

4. **Backup Encryption Test**:
   - Create Cloud SQL backup
   - Verify backup is encrypted with same CMEK
   - Test restore from encrypted backup

**Responsible Party**: Cloud Security Architecture + Data Protection Officer
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-05
**Next Review**: 2025-11-05

---

## SYSTEM AND INFORMATION INTEGRITY (SI) - NIST SP 800-171 §3.14

### SI.L2-3.14.1 - Identify, report, and correct system flaws in a timely manner

**NIST SP 800-171 Rev. 2 Citation**: §3.14.1
**NIST SP 800-53 Rev. 5 Mapping**: SI-2, SI-2(1), SI-2(2), SI-2(3), SI-2(5)
**CMMC Level**: 2
**Practice**: SI.L2-3.14.1

**Implementation Description**:
System flaws (software vulnerabilities, misconfigurations, bugs) are identified through automated scanning, monitoring, and security advisories. Flaws are tracked in JIRA with severity-based SLAs, prioritized for remediation, and verified after patching. Automated remediation is employed where possible through n8n workflows and Ansible playbooks.

**Implementing Tools**:
1. **Trivy** (Primary - Vulnerability Detection)
   - OS package vulnerabilities
   - Application dependencies
   - Configuration issues

2. **n8n** (Primary - Automated Remediation)
   - Patch automation workflows
   - Ticket creation and tracking
   - Validation testing

3. **Ansible** (Supporting - Patch Deployment)
   - Automated patch application
   - Configuration remediation
   - Rollback capabilities

4. **Taiga/JIRA** (Supporting - Flaw Tracking)
   - Vulnerability ticket management
   - SLA tracking
   - Remediation verification

**Technical Configuration**:
```yaml
# n8n Flaw Remediation Workflow
{
  "name": "Automated Flaw Remediation",
  "nodes": [
    {
      "name": "Vulnerability Scanner Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "trivy-vulnerability",
        "responseMode": "onReceived"
      }
    },
    {
      "name": "Severity Filter",
      "type": "n8n-nodes-base.switch",
      "parameters": {
        "rules": {
          "values": [
            {
              "conditions": {
                "string": [
                  {
                    "value1": "={{$json.vulnerability.severity}}",
                    "operation": "equals",
                    "value2": "CRITICAL"
                  }
                ]
              },
              "renameOutput": "critical_auto_remediate"
            },
            {
              "conditions": {
                "string": [
                  {
                    "value1": "={{$json.vulnerability.severity}}",
                    "operation": "equals",
                    "value2": "HIGH"
                  }
                ]
              },
              "renameOutput": "high_create_ticket"
            }
          ]
        }
      }
    },
    {
      "name": "Check if Patch Available",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "https://nvd.nist.gov/rest/json/cve/{{$json.vulnerability.cve_id}}",
        "method": "GET"
      }
    },
    {
      "name": "Auto-Apply Patch",
      "type": "n8n-nodes-base.ansible",
      "parameters": {
        "playbookId": "apply-security-patch.yml",
        "extraVars": {
          "package_name": "={{$json.vulnerability.package_name}}",
          "fixed_version": "={{$json.vulnerability.fixed_version}}",
          "affected_hosts": "={{$json.vulnerability.affected_systems}}"
        }
      }
    },
    {
      "name": "Create JIRA Ticket",
      "type": "n8n-nodes-base.jira",
      "parameters": {
        "operation": "create",
        "project": "SEC",
        "issueType": "Bug",
        "summary": "Security Flaw: {{$json.vulnerability.cve_id}} - {{$json.vulnerability.package_name}}",
        "description": "CVE: {{$json.vulnerability.cve_id}}\\nSeverity: {{$json.vulnerability.severity}}\\nCVSS Score: {{$json.vulnerability.cvss_score}}\\nAffected Package: {{$json.vulnerability.package_name}} {{$json.vulnerability.installed_version}}\\nFixed Version: {{$json.vulnerability.fixed_version}}\\n\\nDescription: {{$json.vulnerability.description}}",
        "priority": "{{$json.vulnerability.severity == 'CRITICAL' ? 'Highest' : 'High'}}",
        "duedate": "={{$json.vulnerability.severity == 'CRITICAL' ? $now.plus({days: 1}) : $now.plus({days: 7})}}"
      }
    },
    {
      "name": "Verify Remediation",
      "type": "n8n-nodes-base.bash",
      "parameters": {
        "command": "trivy image --severity {{$json.vulnerability.severity}} --vuln-type os,library {{$json.vulnerability.image_name}} | grep -q {{$json.vulnerability.cve_id}} && echo 'STILL_VULNERABLE' || echo 'REMEDIATED'"
      }
    },
    {
      "name": "Update Ticket Status",
      "type": "n8n-nodes-base.jira",
      "parameters": {
        "operation": "update",
        "issueKey": "={{$node['Create JIRA Ticket'].json.key}}",
        "fields": {
          "status": "={{$node['Verify Remediation'].json.output == 'REMEDIATED' ? 'Resolved' : 'In Progress'}}"
        }
      }
    }
  ]
}

# Ansible patch deployment playbook
---
- name: Apply Security Patches
  hosts: "{{ affected_hosts | default('all') }}"
  become: yes

  vars:
    patch_log: "/var/log/security-patches.log"

  tasks:
    - name: Log patch operation start
      ansible.builtin.lineinfile:
        path: "{{ patch_log }}"
        line: "{{ ansible_date_time.iso8601 }} - Starting patch for {{ package_name }} to {{ fixed_version }}"
        create: yes

    - name: Take snapshot before patching (GCP)
      gcp_compute_snapshot:
        name: "pre-patch-{{ ansible_hostname }}-{{ ansible_date_time.epoch }}"
        source_disk: "{{ ansible_hostname }}-disk"
        zone: "{{ gcp_zone }}"
        project: "{{ gcp_project }}"
      delegate_to: localhost
      when: cloud_provider == "gcp"

    - name: Update package cache
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600
      when: ansible_os_family == "Debian"

    - name: Install specific package version (security patch)
      ansible.builtin.apt:
        name: "{{ package_name }}={{ fixed_version }}"
        state: present
        force: yes
      when: ansible_os_family == "Debian"
      register: patch_result

    - name: Restart affected services
      ansible.builtin.systemd:
        name: "{{ item }}"
        state: restarted
      loop: "{{ services_to_restart | default([]) }}"
      when: patch_result.changed

    - name: Verify patch applied
      ansible.builtin.shell: |
        dpkg -l | grep {{ package_name }} | awk '{print $3}'
      register: installed_version
      changed_when: false

    - name: Assert correct version installed
      ansible.builtin.assert:
        that:
          - installed_version.stdout == fixed_version
        fail_msg: "Patch verification failed - expected {{ fixed_version }}, got {{ installed_version.stdout }}"
        success_msg: "Patch successfully applied and verified"

    - name: Log patch operation completion
      ansible.builtin.lineinfile:
        path: "{{ patch_log }}"
        line: "{{ ansible_date_time.iso8601 }} - Completed patch for {{ package_name }} - Result: SUCCESS - Version: {{ installed_version.stdout }}"

    - name: Report patch status to compliance system
      ansible.builtin.uri:
        url: "{{ compliance_webhook_url }}"
        method: POST
        body_format: json
        body:
          hostname: "{{ ansible_hostname }}"
          package: "{{ package_name }}"
          old_version: "{{ patch_result.version if patch_result.changed else 'already_patched' }}"
          new_version: "{{ fixed_version }}"
          timestamp: "{{ ansible_date_time.iso8601 }}"
          status: "patched"

  rescue:
    - name: Log patch failure
      ansible.builtin.lineinfile:
        path: "{{ patch_log }}"
        line: "{{ ansible_date_time.iso8601 }} - FAILED patch for {{ package_name }} - Error: {{ ansible_failed_result.msg }}"

    - name: Rollback to snapshot (if needed)
      debug:
        msg: "Manual rollback may be required - snapshot available: pre-patch-{{ ansible_hostname }}-{{ ansible_date_time.epoch }}"
```

**Flaw Remediation SLA Matrix**:
| Severity | CVSS Score | Time to Remediate | Approval Required | Auto-Remediation | Verification |
|----------|------------|------------------|-------------------|------------------|--------------|
| CRITICAL | 9.0-10.0 | 24 hours | Security Lead | Yes (with snapshot) | Automated re-scan |
| HIGH | 7.0-8.9 | 7 days | Team Lead | Yes (non-production) | Automated re-scan |
| MEDIUM | 4.0-6.9 | 30 days | Sprint Planning | No | Weekly scan |
| LOW | 0.1-3.9 | 90 days | Backlog Review | No | Monthly scan |

**Evidence Artifacts**:
- **Location**: gs://compliance-evidence-store/system-integrity/si-3.14.1/
- **Collection Frequency**: Daily scans + Real-time remediation logs
- **Artifacts**:
  - Vulnerability scan reports (Trivy, Grype)
  - Remediation ticket history (JIRA exports)
  - Patch deployment logs (Ansible)
  - SLA compliance reports
  - Verification scan results (pre/post patching)

**Collection Procedure**:
```bash
#!/bin/bash
# Daily flaw remediation evidence collection

DATE=$(date +%Y%m%d)
EVIDENCE_DIR="/tmp/flaw_remediation_${DATE}"
mkdir -p "${EVIDENCE_DIR}"

# 1. Collect open vulnerability tickets
echo "[$(date)] Collecting open vulnerability tickets..."
curl -u "${JIRA_USER}:${JIRA_TOKEN}" \
  "https://jira.internal/rest/api/2/search?jql=project=SEC AND issuetype=Bug AND status!=Resolved AND labels=security-flaw" | \
  jq '{
    total: .total,
    issues: [.issues[] | {
      key: .key,
      summary: .fields.summary,
      priority: .fields.priority.name,
      created: .fields.created,
      duedate: .fields.duedate,
      status: .fields.status.name,
      age_days: ((now - (.fields.created | fromdate)) / 86400 | floor)
    }]
  }' > "${EVIDENCE_DIR}/open_vulnerabilities.json"

# 2. Check for SLA violations
echo "[$(date)] Checking for SLA violations..."
jq '[.issues[] | select(
  (.priority == "Highest" and .age_days > 1) or
  (.priority == "High" and .age_days > 7) or
  (.priority == "Medium" and .age_days > 30) or
  (.priority == "Low" and .age_days > 90)
)] | {
  sla_violations: length,
  violations: .
}' "${EVIDENCE_DIR}/open_vulnerabilities.json" > "${EVIDENCE_DIR}/sla_violations.json"

# 3. Collect patch deployment history
echo "[$(date)] Collecting patch deployment logs..."
gsutil cat gs://ansible-logs/apply-security-patch_$(date +%Y%m)*.log | \
  grep -E "(Starting patch|Completed patch|FAILED patch)" | \
  jq -R -s 'split("\n") | map(select(length > 0))' > "${EVIDENCE_DIR}/patch_history.json"

# 4. Generate remediation summary
python3 << 'EOF' > "${EVIDENCE_DIR}/remediation_summary_${DATE}.json"
import json
from datetime import datetime, timedelta

with open("${EVIDENCE_DIR}/open_vulnerabilities.json") as f:
    vuln_data = json.load(f)

with open("${EVIDENCE_DIR}/sla_violations.json") as f:
    sla_data = json.load(f)

summary = {
    "report_date": "${DATE}",
    "total_open_vulnerabilities": vuln_data["total"],
    "by_priority": {
        "critical": len([v for v in vuln_data["issues"] if v["priority"] == "Highest"]),
        "high": len([v for v in vuln_data["issues"] if v["priority"] == "High"]),
        "medium": len([v for v in vuln_data["issues"] if v["priority"] == "Medium"]),
        "low": len([v for v in vuln_data["issues"] if v["priority"] == "Low"])
    },
    "sla_violations": sla_data["sla_violations"],
    "compliance_status": "COMPLIANT" if sla_data["sla_violations"] == 0 else "NON-COMPLIANT"
}

print(json.dumps(summary, indent=2))
EOF

# 5. Alert on SLA violations
VIOLATIONS=$(jq -r '.sla_violations' "${EVIDENCE_DIR}/sla_violations.json")
if [ "$VIOLATIONS" -gt 0 ]; then
    echo "ALERT: ${VIOLATIONS} SLA violations detected"
    curl -X POST https://chat.googleapis.com/v1/spaces/SECURITY_SPACE/messages \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"⚠️ COMPLIANCE ALERT: ${VIOLATIONS} vulnerability remediation SLA violations detected. Review required.\"}"
fi

# 6. Hash and upload
cd "${EVIDENCE_DIR}"
find . -type f -exec sha256sum {} \; > checksums.sha256

gsutil -m cp -r "${EVIDENCE_DIR}" \
  gs://compliance-evidence-store/system-integrity/si-3.14.1/$(date +%Y)/$(date +%m)/

# Cleanup
rm -rf "${EVIDENCE_DIR}"

echo "[$(date)] Flaw remediation evidence collection complete"
```

**Testing Procedure**:
1. **Detection Test**:
   - Deploy container with known CVE
   - Verify Trivy scan detects vulnerability
   - Confirm JIRA ticket auto-created

2. **Automated Remediation Test**:
   - Trigger n8n workflow for CRITICAL vulnerability
   - Verify snapshot created before patching
   - Confirm patch applied successfully
   - Validate vulnerability resolved in re-scan

3. **SLA Compliance Test**:
   - Identify vulnerabilities approaching SLA deadline
   - Verify escalation notifications sent
   - Track remediation completion before SLA expiry

4. **Rollback Test**:
   - Simulate failed patch deployment
   - Verify snapshot rollback capability
   - Confirm system returns to pre-patch state

**Responsible Party**: Security Engineering + Platform Operations
**Implementation Status**: Fully Implemented
**Last Verification**: 2025-10-04
**Next Review**: 2025-11-04

---

## TOOL-TO-CONTROL MAPPING SUMMARY

### Complete Tool Coverage Matrix

| Tool | Primary Controls | Supporting Controls | Evidence Generated | Auto/Manual |
|------|-----------------|--------------------|--------------------|-------------|
| **Gitea** | AC.L2-3.1.1, AC.L2-3.1.2, CM.L2-3.4.3 | AU.L2-3.3.2, IA.L2-3.5.3 | Access logs, commit history, PR approvals | Auto |
| **SonarQube** | RA.L2-3.11.2, SI.L2-3.14.1 | CA.L2-3.12.1 | SAST reports, code quality metrics | Auto |
| **Trivy** | RA.L2-3.11.2, SI.L2-3.14.1 | CA.L2-3.12.1 | CVE reports, SBOM | Auto |
| **Grype** | RA.L2-3.11.2 | SI.L2-3.14.1 | Vulnerability database matches | Auto |
| **Checkov** | CM.L2-3.4.2, CM.L2-3.4.3 | RA.L2-3.11.2 | IaC policy violations | Auto |
| **tfsec** | CM.L2-3.4.2 | RA.L2-3.11.2 | Terraform security findings | Auto |
| **Atlantis** | CM.L2-3.4.3 | AC.L2-3.1.2 | Terraform plan/apply logs | Auto |
| **Cloud KMS** | SC.L2-3.13.16, SC.L2-3.13.11 | AC.L2-3.1.3, IA.L2-3.5.10 | Key usage logs, rotation history | Auto |
| **Cloud Logging** | AU.L2-3.3.1, AU.L2-3.3.2 | AC.L2-3.1.12, IR.L2-3.6.1 | Audit trails, security events | Auto |
| **Prometheus** | CA.L2-3.12.3, SI.L2-3.14.5 | AU.L2-3.3.4 | Metrics, performance data | Auto |
| **Grafana** | CA.L2-3.12.3 | AC.L2-3.1.12, SI.L2-3.14.6 | Dashboards, visualizations | Auto |
| **Wazuh** | IR.L2-3.6.1, SI.L2-3.14.7 | AC.L2-3.1.7, SI.L2-3.14.2 | SIEM events, HIDS alerts | Auto |
| **n8n** | IR.L2-3.6.1, SI.L2-3.14.1 | AU.L2-3.3.4, RA.L2-3.11.3 | Workflow execution logs | Auto |
| **Packer** | CM.L2-3.4.1 | CM.L2-3.4.2 | Image build manifests | Auto |
| **Ansible** | CM.L2-3.4.1, SI.L2-3.14.1 | RA.L2-3.11.3 | Playbook execution logs | Auto |
| **Security Command Center** | RA.L2-3.11.1, RA.L2-3.11.2 | AC.L2-3.1.20 | Security findings, compliance reports | Auto |
| **Cloud IAM** | AC.L2-3.1.1, AC.L2-3.1.5 | IA.L2-3.5.3, IA.L2-3.5.4 | IAM policy exports, access logs | Auto |
| **Falco** | AC.L2-3.1.7, CM.L2-3.4.7 | SI.L2-3.14.5 | Runtime security events | Auto |
| **osquery** | AC.L2-3.1.5, CM.L2-3.4.8 | AC.L2-3.1.21 | System state queries | Manual queries |
| **Taiga** | IR.L2-3.6.2, CA.L2-3.12.2 | CM.L2-3.4.3 | Incident/task tracking | Manual + Auto |

---

## RESPONSIBLE PARTIES

| Role | Responsibilities | Controls Ownership |
|------|-----------------|-------------------|
| **Security Operations Center (SOC)** | 24/7 monitoring, incident response, alert triage | AU.*, IR.*, SI.L2-3.14.6 |
| **Security Engineering** | Tool implementation, automation, vulnerability management | RA.*, SI.L2-3.14.1, CA.* |
| **Platform Engineering** | Infrastructure baseline, change management, GitOps | CM.*, AC.L2-3.1.2 |
| **Identity and Access Management Team** | User provisioning, MFA enrollment, access reviews | AC.L2-3.1.1, AC.L2-3.1.5, IA.* |
| **Cloud Security Architecture** | Encryption strategy, network security, compliance design | SC.*, AC.L2-3.1.3 |
| **Audit and Compliance Team** | Evidence collection, assessments, auditor liaison | CA.*, AU.L2-3.3.2 |
| **DevOps Engineering** | CI/CD pipeline, security gate implementation | CM.L2-3.4.3, RA.L2-3.11.2 |
| **Data Protection Officer** | CUI handling, privacy controls, retention policies | SC.L2-3.13.16, SC.L2-3.13.11 |

---

## CONTINUOUS MONITORING

All controls are subject to continuous automated monitoring with the following frequencies:

- **Real-time**: Access attempts, authentication events, security alerts
- **Daily**: Vulnerability scans, configuration drift detection, access reviews
- **Weekly**: Compliance posture assessments, SLA tracking
- **Monthly**: Control effectiveness testing, tabletop exercises
- **Quarterly**: Comprehensive security assessments, auditor walkthroughs
- **Annually**: Full CMMC assessment, penetration testing, policy review

---

**Document Control**:
- **Classification**: Internal Use Only
- **Owner**: Compliance Team
- **Review Frequency**: Quarterly
- **Next Review Date**: 2026-01-05
- **Approval**: Security Lead, CTO, Compliance Officer
