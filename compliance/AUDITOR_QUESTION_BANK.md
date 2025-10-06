# Auditor Question Bank
## CMMC 2.0 Level 2 Assessment Preparation

**Document Version**: 1.0
**Assessment Date**: 2025-10-05
**System**: Gitea DevSecOps Platform on GCP
**Purpose**: Prepare team for assessor interviews and evidence requests

---

## How to Use This Document

This question bank contains:
- Common questions assessors ask during CMMC Level 2 assessments
- Prepared responses with evidence citations
- Demonstration procedures for each control
- Personnel responsible for answering each question

**Interview Preparation**:
1. Relevant personnel should review questions in their domain
2. Practice responses using the talking points provided
3. Know where evidence artifacts are located
4. Be prepared to demonstrate controls live

---

## ACCESS CONTROL (AC) DOMAIN

### AC.L2-3.1.1 - System Access Limitation

**Assessor Question 1**: "How do you ensure only authorized users can access the Gitea platform?"

**Prepared Response**:
"We implement multi-layered access controls:
- **Authentication**: All users authenticate through Gitea with mandatory MFA after a 7-day enrollment period. We also offer OAuth2 integration with our enterprise IdP.
- **Authorization**: Role-based access control restricts permissions based on job function. Default is deny-all; permissions are explicitly granted.
- **Provisioning**: User accounts require formal access request through JIRA with manager approval before creation.
- **Monitoring**: Daily exports of user account inventory verify no unauthorized accounts exist.
- **Session Management**: Sessions timeout after 30 minutes of inactivity."

**Evidence to Show**:
1. User account inventory export (gs://compliance-evidence-store/access-control/ac-3.1.1/[DATE]/user_inventory.json)
2. Gitea configuration showing MFA enforcement (app.ini file)
3. Sample access request approval in JIRA
4. Authentication logs from Cloud Logging

**Demonstration**:
1. Show Gitea user management interface with RBAC roles
2. Attempt login without MFA (demonstrate enforcement)
3. Display real-time authentication logs in Grafana dashboard
4. Show session timeout by waiting for inactivity period

**Who Responds**: IAM Team Lead, Security Operations

---

**Assessor Question 2**: "Do you have any shared accounts or generic usernames?"

**Prepared Response**:
"No. Our policy prohibits shared accounts. Every user has a unique identifier (email address). Service accounts used for automation are clearly labeled (e.g., gitea-cicd-runner@project.iam.gserviceaccount.com) and have dedicated purposes. We run weekly scans to detect potential shared account patterns - our last scan on [DATE] showed zero shared accounts."

**Evidence to Show**:
1. User identity inventory showing unique email addresses
2. Shared account detection script output (zero findings)
3. Service account naming policy documentation

**Demonstration**:
```bash
# Run shared account detection
curl -H "Authorization: token ${GITEA_TOKEN}" \
  https://gitea.internal/api/v1/admin/users | \
  jq 'group_by(.email) | map(select(length > 1))'
# Output: [] (empty array = no duplicates)
```

**Who Responds**: IAM Team Lead

---

### AC.L2-3.1.2 - Transaction and Function Limitation

**Assessor Question 1**: "How do you prevent developers from directly deploying to production without proper approvals?"

**Prepared Response**:
"We enforce separation through multiple technical controls:
- **Branch Protection**: The 'main' branch in Gitea requires 2 peer approvals and cannot be directly pushed to - all changes must go through pull requests.
- **CI/CD Gates**: Our Atlantis-based GitOps workflow requires security scan pass + peer review + explicit 'atlantis apply' comment before infrastructure changes are deployed.
- **Policy Enforcement**: Terraform Sentinel policies block changes that violate security or cost thresholds.
- **Role Separation**: Developers can create pull requests but cannot merge their own PRs or approve infrastructure changes affecting IAM/KMS resources."

**Evidence to Show**:
1. Gitea branch protection configuration (API export)
2. Atlantis plan/apply audit logs showing approval workflow
3. Sentinel policy files (version-controlled)
4. Attempted direct push to main (denied by branch protection)

**Demonstration**:
1. Show pull request workflow in Gitea
2. Demonstrate required approval matrix (CODEOWNERS file)
3. Attempt to merge PR without required approvals (blocked)
4. Show Atlantis requiring explicit approval comment

**Who Responds**: DevOps Engineering Lead, Platform Engineering

---

### AC.L2-3.1.5 - Least Privilege

**Assessor Question 1**: "How do you ensure users and service accounts have only the minimum necessary permissions?"

**Prepared Response**:
"We implement least privilege systematically:
- **Custom IAM Roles**: We do not use broad pre-defined roles like 'Editor' or 'Owner'. Instead, we create custom roles with minimal permissions (e.g., CI/CD service account has only storage.objects.create, not broad Storage Admin).
- **Default Deny**: All GCP resources default to no access; permissions are explicitly granted based on documented business need.
- **Quarterly Access Reviews**: Managers attest that their team members still require current permissions. Unused permissions are removed.
- **Automated Detection**: osquery monitors for privilege escalation attempts (unauthorized sudo usage, setuid execution).
- **Time-Limited Access**: Privileged access auto-expires after 8 hours for non-emergency operations."

**Evidence to Show**:
1. IAM policy export showing custom roles and minimal permissions
2. Sample custom role definition (e.g., cicdRunner with specific permissions)
3. Quarterly access review report with manager sign-offs
4. osquery privilege escalation detection logs

**Demonstration**:
1. Show GCP IAM console with custom roles
2. Display service account permissions (highlight specific grants, not wildcards)
3. Run osquery: `SELECT * FROM sudoers;` and review results
4. Attempt operation without sufficient permission (demonstrate denial)

**Who Responds**: IAM Team Lead, Cloud Security Architect

---

**Assessor Question 2**: "How often do you review and recertify user access?"

**Prepared Response**:
"We conduct multi-layered access reviews:
- **Daily**: Automated scan for new accounts, changes to privileged roles (alerts if unexpected)
- **Weekly**: Service account permission audit via automated script
- **Monthly**: Privileged access grants reviewed (break-glass access, temporary elevations)
- **Quarterly**: Comprehensive user access review - managers attest to continued need for each team member's permissions
- **Annually**: Third-party assessment validates our access control implementation

Our last quarterly review completed on [DATE] resulted in removal of 5 unused permissions and deactivation of 2 accounts for separated employees."

**Evidence to Show**:
1. Quarterly access review report (manager attestations)
2. Access review schedule documentation
3. Sample permission removal tickets (JIRA)

**Who Responds**: IAM Team Lead, Compliance Team

---

## AUDIT AND ACCOUNTABILITY (AU) DOMAIN

### AU.L2-3.3.1 - Audit Record Creation and Retention

**Assessor Question 1**: "What events do you log and how long do you retain audit logs?"

**Prepared Response**:
"We implement comprehensive logging across all system layers:

**Events Logged**:
- Authentication (login, logout, failed attempts, MFA verification)
- Authorization (permission grants/denials, role changes)
- Resource access (repository operations, file access, API calls)
- Administrative actions (user creation, configuration changes, security policy updates)
- Security events (vulnerability detections, incident response actions)

**Retention Periods**:
- Application logs (Gitea, n8n): 1 year hot storage, 6 additional years in GCS archive
- Cloud Audit Logs: 400 days (GCP Admin Activity) to 3 years (custom retention)
- Security events (Wazuh): 3 years
- Compliance-critical records: 7 years minimum

**Log Protection**: All logs are immutable (cannot be modified after creation), encrypted at rest with AES-256, and stored with retention policies that prevent premature deletion."

**Evidence to Show**:
1. Daily log export archive with hash verification
2. Cloud Logging retention policy configuration (locked status)
3. Sample audit log records showing all required fields
4. Log completeness report (no gaps in timestamp sequences)

**Demonstration**:
1. Show Cloud Logging retention configuration
2. Display sample logs in Grafana (authentication, admin actions, security events)
3. Demonstrate log immutability (attempt to modify, verify failure)
4. Export logs and verify hash matches stored hash

**Who Responds**: Security Logging Team, Cloud Operations

---

**Assessor Question 2**: "How do you ensure audit logs haven't been tampered with?"

**Prepared Response**:
"We implement multiple integrity protections:
- **Immutability**: Cloud Logging writes are append-only; once written, logs cannot be modified or deleted (enforced by GCP platform)
- **Retention Lock**: GCS buckets containing archived logs have locked retention policies (cannot be overridden even by bucket owner)
- **Hash Verification**: Daily log exports are SHA-256 hashed; hashes stored separately and verified during evidence collection
- **Access Controls**: Log deletion permission not granted to any human users (only to automated retention service account)
- **Monitoring**: Attempts to access or modify audit logs trigger alerts to security team

We can demonstrate the complete integrity chain from log creation through long-term archival."

**Evidence to Show**:
1. Hash verification chain (checksums.sha256 files)
2. IAM policy showing restrictive log access
3. Retention policy lock status
4. Audit logs of audit log access (meta-logging)

**Demonstration**:
```bash
# Verify log integrity
gsutil cat gs://compliance-evidence-store/audit-logs/daily-exports/20251005/audit_logs.json.gz | \
  gunzip | \
  sha256sum
# Compare to stored hash
gsutil cat gs://compliance-evidence-store/audit-logs/daily-exports/20251005/audit_logs.json.gz.sha256
```

**Who Responds**: Security Logging Team, Compliance Team

---

### AU.L2-3.3.8 - Protect Audit Information

**Assessor Question**: "Who has access to audit logs and how is this access controlled?"

**Prepared Response**:
"Audit log access is strictly controlled via IAM policies:

**Read Access** (View Only):
- Security Operations: Read access for monitoring and incident investigation
- Compliance Team: Read access for audit evidence collection
- System Admins: Limited read access to system logs only (not security logs)

**No Modification/Deletion Access**: Zero users have permission to modify or delete audit logs. Logs are immutable by design.

**Access Logging**: All audit log access is itself audited - we log who viewed which logs and when.

**Monitoring**: Real-time alerts trigger if:
- Unauthorized user attempts log access (denied by IAM)
- Retention policy modification attempted (should never occur)
- Unusual volume of log queries (potential exfiltration attempt)

Developers do NOT have access to audit logs - they can only view application debug logs in non-production environments."

**Evidence to Show**:
1. IAM policy export showing log viewer roles
2. Denied access attempts in Cloud Audit Logs
3. Alert configuration for unauthorized log access

**Who Responds**: IAM Team Lead, Security Logging Team

---

## CONFIGURATION MANAGEMENT (CM) DOMAIN

### CM.L2-3.4.1 - Baseline Configurations

**Assessor Question 1**: "How do you establish and maintain baseline configurations?"

**Prepared Response**:
"We use Infrastructure as Code to define and enforce baselines:

**Baseline Creation**:
- **Compute Instances**: CIS Ubuntu 22.04 LTS Benchmark Level 1 hardening, built with Packer, stored as versioned golden images
- **Containers**: Minimal base images (distroless/Alpine), non-root user, read-only filesystem
- **Infrastructure**: Terraform modules define baseline network, IAM, encryption configurations
- **All Baselines**: Version-controlled in Git, reviewed through pull request workflow

**Baseline Maintenance**:
- **Quarterly Review**: Security team reviews CIS benchmark updates and new vulnerabilities
- **Automated Validation**: Weekly CIS-CAT scanner validates instances against benchmarks (target >95% compliance)
- **Drift Detection**: Daily Terraform plan identifies configuration drift from baseline
- **Updates**: Baseline updates deployed through standard change management process

Current baseline version: v2.1.0 (last updated 2025-10-01), compliance score: 97.3%"

**Evidence to Show**:
1. Terraform modules defining baselines (version-controlled)
2. Packer templates and build manifests
3. CIS-CAT assessment reports showing compliance scores
4. Baseline change history in Git

**Demonstration**:
1. Show Terraform baseline module code
2. Run CIS-CAT scanner on sample instance
3. Display compliance dashboard (Grafana)
4. Demonstrate drift detection (terraform plan)

**Who Responds**: Platform Engineering Lead, Security Compliance

---

**Assessor Question 2**: "Can you show me how you detect if someone manually changes a configuration outside of your IaC process?"

**Prepared Response**:
"We have multiple drift detection mechanisms:

**Daily Terraform Drift Detection**:
- Automated terraform plan runs daily across all environments
- Compares actual infrastructure state to desired state in Terraform
- Alerts if drift detected (e.g., someone changed a firewall rule via GCP Console)
- Slack notification to ops team with drift details

**File Integrity Monitoring** (Wazuh):
- Monitors critical configuration files (/etc/, SSH keys)
- Real-time alerts on unauthorized changes
- Automated remediation playbooks can revert changes

**Weekly Baseline Validation**:
- CIS-CAT scanner validates instance configurations
- Configuration drift report generated
- Non-compliant instances flagged for remediation

**Enforcement**:
- GitOps policy requires all infrastructure changes via Terraform
- GCP Console access limited to break-glass scenarios (rarely used, heavily logged)"

**Evidence to Show**:
1. Daily terraform plan output showing drift detection
2. Wazuh FIM alerts (sample unauthorized change)
3. Configuration drift reports

**Demonstration**:
```bash
# Show terraform drift detection
cd /terraform/gitea-platform
terraform plan | grep "Note: Objects have changed outside of Terraform"

# Manual change detection
gcloud compute firewall-rules list --format=json | \
  jq '.[] | select(.description | contains("MANAGED BY TERRAFORM") | not)'
```

**Who Responds**: Platform Engineering, Security Operations

---

### CM.L2-3.4.3 - Change Control

**Assessor Question**: "Walk me through your change management process from proposal to deployment."

**Prepared Response**:
"Our GitOps-based change management process:

**1. Proposal**:
- Developer creates feature branch, makes infrastructure changes in Terraform
- Commits signed with GPG key (proves developer identity)
- Opens Pull Request in Gitea

**2. Automated Review**:
- Atlantis runs terraform plan (shows what will change)
- Security scans: Checkov, tfsec, Terrascan validate security compliance
- Cost analysis: Infracost estimates monthly cost delta
- Results posted as PR comments within 5 minutes

**3. Peer Review** (Human Approval):
- Minimum 2 reviewers required (defined in CODEOWNERS file)
- Security-sensitive changes (IAM, KMS): Security team must approve
- Cost impact >$500/month: Engineering Manager must approve
- Author cannot approve own PR

**4. Deployment**:
- After approvals, reviewer comments 'atlantis apply'
- Atlantis executes terraform apply with full audit logging
- Deployment logs include: approver identity, timestamp, changeset

**5. Validation**:
- Automated tests verify deployment
- Configuration drift detection confirms actual state matches desired
- Security posture re-scanned

**Emergency Changes**: Break-glass process allows expedited deployment with retroactive approval within 24 hours."

**Evidence to Show**:
1. Sample pull request with complete approval chain
2. Atlantis plan/apply logs
3. Security scan results attached to PR
4. Post-deployment validation results

**Demonstration**:
1. Live walkthrough of pull request workflow in Gitea
2. Show Atlantis terraform plan output in PR comments
3. Display approval requirements (branch protection settings)
4. Review audit trail for recently-deployed change

**Who Responds**: DevOps Engineering Lead, Platform Engineering

---

## IDENTIFICATION AND AUTHENTICATION (IA) DOMAIN

### IA.L2-3.5.3 - Multifactor Authentication

**Assessor Question 1**: "Is MFA required for all users? How is this enforced?"

**Prepared Response**:
"Yes, MFA is universally required:

**Gitea Users** (All personnel):
- MFA mandatory after 7-day grace period for new accounts
- Supported methods: TOTP (Google Authenticator, Authy), WebAuthn/FIDO2 hardware keys
- Enrollment: Users see persistent banner until MFA configured; after grace period, login blocked until MFA enabled
- Current enrollment: 100% of active users have MFA (verified daily via API export)

**GCP Users** (Cloud platform access):
- 2-Step Verification enforced at Cloud Identity organization policy level
- Privileged users (roles with IAM, KMS permissions): Hardware security key REQUIRED - TOTP not sufficient
- Enforcement: Conditional Access policy denies access without proper MFA method

**Service Accounts**: Do not use MFA (they're non-interactive), but compensating control is Workload Identity Federation (binds service account to specific workload, can't export keys)

**Monitoring**: Daily report shows MFA enrollment status; non-compliant accounts escalated to managers for immediate remediation."

**Evidence to Show**:
1. MFA enrollment report (100% coverage)
2. Gitea configuration (MFA grace period setting)
3. GCP Organization Policy enforcing 2SV
4. Sample MFA verification log

**Demonstration**:
1. Show Gitea MFA enrollment interface
2. Login with MFA (demonstrate TOTP or hardware key)
3. Attempt login without MFA (blocked after grace period)
4. Display MFA enrollment dashboard (Grafana)

**Who Responds**: IAM Team Lead, Security Operations

---

**Assessor Question 2**: "What happens if a user loses their MFA device?"

**Prepared Response**:
"We have a secure MFA recovery process:

**Immediate Actions**:
1. User contacts Security team via ticketing system
2. Security verifies user identity through out-of-band method (phone call to registered number, verification with manager)
3. Security temporarily resets MFA for that user (logged action)
4. User must re-enroll MFA within 4 hours or account re-locked

**Prevention**:
- Users generate scratch/recovery codes at MFA enrollment (single-use, rate-limited)
- Recommendation to enroll multiple MFA methods (both TOTP and hardware key)

**Monitoring**:
- MFA resets are logged and reviewed weekly (detect patterns indicating social engineering)
- Excessive MFA lockouts trigger investigation

**Average Recovery Time**: <2 hours during business hours"

**Evidence to Show**:
1. MFA reset procedure documentation
2. Sample MFA reset ticket (sanitized)
3. MFA reset audit log

**Who Responds**: IAM Team, Security Operations

---

## INCIDENT RESPONSE (IR) DOMAIN

### IR.L2-3.6.1 - Incident Handling Capability

**Assessor Question 1**: "Describe your incident response process from detection through recovery."

**Prepared Response**:
"Our incident response process is heavily automated:

**1. Detection** (Mean Time to Detect: <5 minutes):
- Wazuh SIEM monitors security events 24/7
- Falco detects runtime anomalies
- Security Command Center flags GCP misconfigurations
- Automated detection rules mapped to MITRE ATT&CK framework

**2. Triage** (Automated severity classification):
- n8n workflow receives alert from Wazuh
- Severity classified (CRITICAL/HIGH/MEDIUM/LOW) based on MITRE tactic, affected asset, data classification
- CRITICAL: Immediate page to on-call via PagerDuty

**3. Containment** (Mean Time to Contain: <15 minutes):
- Automated playbooks execute via Ansible:
  - Network isolation: Modify VPC firewall to quarantine affected instance
  - Account suspension: Disable compromised user in Gitea and Cloud IAM
  - Process kill: Terminate malicious process
- Manual approval required only for production service disruption

**4. Investigation**:
- Forensic snapshot automatically captured
- Logs aggregated (Wazuh, Cloud Logging, VPC flows)
- Timeline generated showing attacker activity

**5. Eradication**:
- Remove malware, close backdoors
- Patch vulnerability that allowed compromise
- Rotate compromised credentials

**6. Recovery**:
- Restore services from clean backups if needed
- Validate system integrity (CIS-CAT scan)
- Enhanced monitoring for 30 days post-recovery

**7. Post-Incident**:
- Lessons learned within 5 business days
- Playbook updates
- Executive report to leadership

**Testing**: Quarterly tabletop exercises, monthly simulated incidents"

**Evidence to Show**:
1. Incident Response Plan documentation
2. Sample incident ticket (JIRA) with complete timeline
3. Automated playbook execution logs (Ansible)
4. Tabletop exercise reports

**Demonstration**:
1. Trigger test alert in Wazuh (pre-configured safe scenario)
2. Show n8n workflow auto-creating JIRA ticket
3. Display containment playbook execution
4. Review incident dashboard (Grafana)

**Who Responds**: Security Operations Manager, Incident Response Lead

---

**Assessor Question 2**: "How do you test your incident response capabilities?"

**Prepared Response**:
"We test incident response at multiple levels:

**Monthly** - Simulated Incident Drills:
- Inject test alert into Wazuh (e.g., simulated brute force attack)
- Verify automated workflows trigger correctly
- SOC team practices manual investigation steps
- Metrics tracked: MTTD (Mean Time to Detect), MTTR (Mean Time to Respond)

**Quarterly** - Tabletop Exercises:
- Scenario-based exercises (ransomware, insider threat, DDoS, data breach)
- Cross-functional participation (Security, DevOps, Legal, PR, Leadership)
- Facilitated discussion of response decisions
- Findings documented, playbooks updated

**Annually** - Full-Scale Incident Response Test:
- Live containment exercise in isolated environment
- Includes actual playbook execution, communication procedures, recovery validation
- External facilitator evaluates performance

**Continuous** - Real Incidents:
- Every real incident triggers post-incident review
- Lessons learned fed back into playbook improvements

**Last Exercise**: 2025-09-15 (ransomware tabletop) - Result: Identified gap in legal notification timeline, updated runbook"

**Evidence to Show**:
1. Tabletop exercise reports (scenarios, lessons learned)
2. Simulated incident drill logs
3. Incident response metrics dashboard (MTTD, MTTR trends)

**Who Responds**: Security Operations Manager, Incident Response Lead

---

## RISK ASSESSMENT (RA) DOMAIN

### RA.L2-3.11.2 - Vulnerability Scanning

**Assessor Question 1**: "How frequently do you scan for vulnerabilities and what do you scan?"

**Prepared Response**:
"We implement continuous vulnerability scanning across all layers:

**Source Code** (SAST) - Every Commit:
- SonarQube, Semgrep, Bandit scan on every pull request
- CRITICAL/HIGH findings block merge (quality gate)
- Covers: SQL injection, XSS, insecure deserialization, OWASP Top 10

**Container Images** - Every Build + Daily Registry Scan:
- Trivy and Grype scan all containers before production deployment
- Daily scan of existing registry images (catch newly-published CVEs)
- CRITICAL vulnerabilities block image push

**Infrastructure as Code** - Every PR + Weekly:
- Checkov, tfsec, Terrascan validate Terraform and Kubernetes
- Policy violations block terraform apply

**Runtime Applications** (DAST) - Weekly (Staging), Monthly (Production):
- OWASP ZAP authenticated scans of web applications and APIs

**Cloud Infrastructure** - Continuous:
- Security Command Center real-time scanning of all GCP resources
- Detects misconfigurations, unpatched VMs, weak IAM bindings

**OS and Packages** - Weekly:
- Trivy scans compute instances for OS vulnerabilities

**Last 30 Days Statistics**:
- Total scans performed: 1,247
- Vulnerabilities detected: 89 (12 CRITICAL, 34 HIGH, 43 MEDIUM)
- Remediated within SLA: 98.8%"

**Evidence to Show**:
1. Vulnerability scan reports (Trivy, SonarQube, ZAP)
2. SBOM files for production containers
3. Security Command Center findings export
4. Scan frequency validation (timestamps in evidence archives)

**Demonstration**:
```bash
# Live container scan
trivy image gcr.io/project/gitea:latest --severity HIGH,CRITICAL

# Show SonarQube quality gate
curl -u $SONAR_TOKEN: \
  "https://sonar.internal/api/qualitygates/project_status?projectKey=gitea-platform"
```

**Who Responds**: Security Engineering Lead, Application Security

---

**Assessor Question 2**: "What is your remediation timeline for vulnerabilities?"

**Prepared Response**:
"We have risk-based remediation SLAs:

**CRITICAL** (CVSS 9.0-10.0 or actively exploited):
- Timeline: 24 hours
- Auto-Remediation: Yes (automated patch deployment with rollback capability)
- Escalation: Immediate page to Security Lead + CTO

**HIGH** (CVSS 7.0-8.9):
- Timeline: 7 days
- Auto-Remediation: Partial (automated in non-production first)
- Escalation: Email to Security Team + Product Owner

**MEDIUM** (CVSS 4.0-6.9):
- Timeline: 30 days
- Auto-Remediation: No (manual review and deployment)
- Escalation: Addressed in sprint planning

**LOW** (CVSS 0.1-3.9):
- Timeline: 90 days or next major release
- Auto-Remediation: No
- Escalation: Backlog prioritization

**Remediation Workflow**:
1. Vulnerability detected → n8n creates JIRA ticket
2. Ticket assigned to package owner (from CODEOWNERS)
3. Developer patches, submits PR
4. Security scan validates fix
5. PR merged → automated deployment
6. Re-scan confirms vulnerability absent
7. Ticket auto-closed

**Current SLA Compliance**: 98.8% (89 of 90 vulnerabilities remediated within SLA last month; 1 MEDIUM finding had approved exception)"

**Evidence to Show**:
1. Remediation SLA policy document
2. JIRA vulnerability ticket tracking (finding → fix → verification)
3. SLA compliance report
4. Sample exception approval (compensating controls documented)

**Who Responds**: Security Engineering Lead, Vulnerability Management

---

## SYSTEM AND COMMUNICATIONS PROTECTION (SC) DOMAIN

### SC.L2-3.13.16 - Encrypt CUI at Rest

**Assessor Question**: "How do you ensure all CUI data is encrypted at rest?"

**Prepared Response**:
"All CUI is protected with FIPS 140-2 validated encryption:

**Encryption Implementation**:
- **Algorithm**: AES-256 (GCM for Cloud Storage, XTS for persistent disks)
- **Key Management**: Customer-Managed Encryption Keys (CMEK) in Cloud KMS
- **Key Protection**: Keys stored in HSM-backed key rings (FIPS 140-2 Level 3 validated)
- **Key Rotation**: Automated every 90 days

**CUI Data Stores**:
- **GCS Buckets** (repositories, backups): CMEK encryption, verified by `data_classification: cui` label
- **Cloud SQL** (Gitea database): Transparent Data Encryption (TDE) + CMEK
- **Persistent Disks** (compute storage): CMEK encryption
- **Secrets** (API keys): Secret Manager with envelope encryption

**Enforcement**:
- Terraform policy REQUIRES CMEK for any resource labeled `data_classification: cui`
- Automated daily scan verifies all CUI resources encrypted
- Unencrypted CUI detection triggers CRITICAL alert

**Validation**:
- Daily encryption status report: Last scan (2025-10-05) - 100% compliance (47 CUI resources, all encrypted with CMEK)
- Key usage audit logs track Encrypt/Decrypt operations

**FIPS Validation**:
- GCP Cloud KMS: FIPS 140-2 validated (Certificate #3318, #3249)
- Validation documentation: https://cloud.google.com/security/compliance/fips-140-2-validated"

**Evidence to Show**:
1. Encryption verification report (all CUI resources encrypted)
2. KMS key configuration (algorithm, rotation period, HSM backing)
3. Key usage audit logs
4. FIPS 140-2 validation certificates

**Demonstration**:
```bash
# Verify GCS bucket encryption
gsutil stat gs://gitea-cui-repositories/sample-file | grep "Encryption:"
# Output: Encryption: Customer-managed key

# Show KMS key details
gcloud kms keys describe cui-storage-encryption-key \
  --location=us-central1 \
  --keyring=cui-keyring
# Shows: rotation_period: 7776000s (90 days), protection_level: HSM
```

**Who Responds**: Cloud Security Architect, Data Protection Officer

---

## SUMMARY

### Key Interview Talking Points

**Access Control**: MFA enforced, least privilege via custom IAM roles, quarterly access reviews, no shared accounts

**Audit Logs**: Comprehensive logging, 3-7 year retention, immutable storage, hash verification

**Configuration Management**: IaC baselines (CIS Level 1), version-controlled, daily drift detection, CIS-CAT validation

**Change Control**: GitOps with Atlantis, 2-person approval, security scanning gates, complete audit trail

**MFA**: 100% user enrollment, hardware keys for privileged users, secure recovery process

**Incident Response**: Automated detection/containment (<15 min MTTR), quarterly tabletops, documented lessons learned

**Vulnerability Management**: Continuous scanning, 24-hour CRITICAL SLA (98.8% compliance), automated remediation

**Encryption**: FIPS 140-2 validated AES-256, CMEK for CUI, 90-day key rotation, 100% coverage

### Evidence Retrieval

All evidence artifacts are stored in: `gs://compliance-evidence-store/[CONTROL_FAMILY]/[CONTROL_ID]/[DATE]/`

**Quick Access**:
```bash
# List evidence for specific control
gsutil ls gs://compliance-evidence-store/access-control/ac-3.1.1/

# Download today's evidence package
gsutil -m cp -r gs://compliance-evidence-store/*/$(date +%Y%m%d) ./evidence-export/

# Verify evidence integrity
find ./evidence-export -name "*.sha256" -exec sha256sum -c {} \;
```

### Personnel Responsibilities

| Domain | Primary | Backup | Executive |
|--------|---------|--------|-----------|
| Access Control | IAM Team Lead | Security Operations | CISO |
| Audit & Accountability | Security Logging | Compliance Team | CISO |
| Configuration Mgmt | Platform Engineering | DevOps Lead | CTO |
| Identification & Auth | IAM Team | Security Operations | CISO |
| Incident Response | SOC Manager | IR Lead | CISO |
| Risk Assessment | Security Engineering | AppSec Lead | CISO |
| System Protection | Cloud Security Architect | Network Engineering | CTO |

---

**Assessment Preparation Checklist**:
- [ ] All evidence artifacts collected for past 90 days
- [ ] Hash verification performed on all evidence
- [ ] Interview participants identified and trained
- [ ] Demonstration environment configured
- [ ] Evidence retrieval procedures tested
- [ ] Executive briefing completed
- [ ] System access credentials prepared for assessor

**Document Control**:
- **Classification**: Internal Use - Assessment Preparation
- **Version**: 1.0
- **Owner**: Compliance Team
- **Review Before**: Each CMMC assessment
