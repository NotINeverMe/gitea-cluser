# System Security Plan (SSP) Structure
## DevSecOps Platform - NIST SP 800-171 Rev. 2 Aligned

### DOCUMENT CONTROL
- **System Name**: Gitea DevSecOps Security Platform
- **System Identifier**: GDSP-2025-001
- **Version**: 1.0 DRAFT
- **Classification**: Controlled Unclassified Information (CUI)
- **Compliance Frameworks**: NIST SP 800-171 Rev. 2, CMMC 2.0 Level 2
- **Last Updated**: January 2025
- **Next Review**: July 2025

---

## 1. SYSTEM IDENTIFICATION

### 1.1 System Name and Title
**Full Name**: Gitea-based DevSecOps Security and Compliance Platform
**Short Name**: GDSP
**System Type**: Major Application

### 1.2 System Categorization
**Information Types**:
- Source Code (Moderate Impact)
- Configuration Data (Moderate Impact)
- Security Scan Results (Moderate Impact)
- Audit Logs (High Impact)

**FIPS 199 Categorization**: MODERATE
**Overall System Categorization**: (Confidentiality: MODERATE, Integrity: HIGH, Availability: MODERATE)

### 1.3 System Owner Information
- **System Owner**: [Organization Security Officer]
- **Authorizing Official**: [Chief Information Security Officer]
- **System Security Officer**: [DevSecOps Security Lead]
- **Technical POC**: [Platform Engineering Lead]

---

## 2. SYSTEM DESCRIPTION

### 2.1 System Purpose and Functions
The GDSP provides enterprise-grade security scanning, compliance automation, and continuous monitoring for software development lifecycle (SDLC) activities. Core functions include:

1. **Security Scanning**: Automated SAST, DAST, container, and IaC security analysis
2. **Compliance Automation**: Control implementation and evidence collection for CMMC 2.0 and NIST SP 800-171 Rev. 2
3. **Continuous Monitoring**: Real-time security posture tracking and alerting
4. **GitOps Integration**: Policy-as-code enforcement through Terraform and Packer

### 2.2 System Environment
**Deployment Model**: Hybrid (Self-hosted Gitea + GCP Services)
**Architecture**: Microservices with container orchestration
**Network Zones**: DMZ, Build Zone, Production Zone, Compliance Zone

### 2.3 System Interconnections
| System | Interface Type | Data Exchanged | Security Controls |
|--------|---------------|----------------|-------------------|
| GCP Security Command Center | REST API | Security findings | mTLS, OAuth 2.0 |
| Gitea Repository | Webhooks | Code events | HMAC signatures |
| CI/CD Runners | gRPC | Build artifacts | Service mesh, mTLS |
| Monitoring Stack | Prometheus | Metrics | Internal only |

---

## 3. CONTROL IMPLEMENTATION

### 3.1 Access Control Family

#### AC.L2-3.1.1 - Limit System Access
**Implementation Status**: Implemented
**Control Implementation Description**:
- Gitea enforces RBAC with OIDC/SAML integration
- GCP IAM provides identity federation with MFA requirement
- Network segmentation via VPC Service Controls
- Zero Trust access model with BeyondCorp principles

**Evidence**:
- RBAC configuration exports (monthly)
- Access review reports (quarterly)
- Authentication logs (continuous)

#### AC.L2-3.1.2 - Limit Transaction Functions
**Implementation Status**: Implemented
**Control Implementation Description**:
- Terraform Sentinel policies enforce transaction limits
- Atlantis provides PR-based approval workflows
- API rate limiting via Cloud Armor
- Function-level access control in application code

**Evidence**:
- Sentinel policy definitions
- API gateway configurations
- Transaction logs with approval chains

#### AC.L2-3.1.3 - Control CUI Flow
**Implementation Status**: Implemented
**Control Implementation Description**:
- Data Loss Prevention (DLP) scanning in CI/CD pipelines
- Encryption in transit via TLS 1.3 minimum
- Encryption at rest via Cloud KMS with CMEK
- Network segmentation and firewall rules

**Evidence**:
- DLP scan reports
- Certificate transparency logs
- KMS key rotation records
- Network flow logs

### 3.2 Audit and Accountability Family

#### AU.L2-3.3.1 - System Audit Records
**Implementation Status**: Implemented
**Control Implementation Description**:
- Cloud Logging aggregates all system logs
- Structured logging with correlation IDs
- Minimum 3-year retention for audit logs
- Tamper-evident log storage with hash chains

**Evidence**:
- Log retention policies
- Sample audit records
- Log integrity verification reports

#### AU.L2-3.3.2 - Review and Update Logged Events
**Implementation Status**: Implemented
**Control Implementation Description**:
- Monthly review of logged event types
- Automated analysis via BigQuery
- Security-relevant events prioritized
- Compliance dashboard for event tracking

**Evidence**:
- Event review meeting minutes
- BigQuery analysis reports
- Updated logging configurations

### 3.3 Configuration Management Family

#### CM.L2-3.4.1 - Baseline Configurations
**Implementation Status**: Implemented
**Control Implementation Description**:
- Packer creates hardened golden images
- Ansible playbooks enforce CIS benchmarks
- Infrastructure as Code via Terraform
- Immutable infrastructure patterns

**Evidence**:
- Golden image manifests
- CIS benchmark scan results
- Terraform state files
- Configuration drift reports

#### CM.L2-3.4.2 - Security Configuration Settings
**Implementation Status**: Implemented
**Control Implementation Description**:
- STIG/CIS hardening applied to all systems
- Automated compliance scanning via Checkov/tfsec
- Security baselines version controlled
- Continuous compliance monitoring

**Evidence**:
- Hardening checklists
- Compliance scan reports
- Git commit history
- Real-time compliance dashboards

### 3.4 Identification and Authentication Family

#### IA.L2-3.5.3 - Multifactor Authentication
**Implementation Status**: Implemented
**Control Implementation Description**:
- FIDO2/WebAuthn for privileged accounts
- TOTP/SMS for standard users
- Risk-based authentication with adaptive MFA
- Hardware token support for administrators

**Evidence**:
- MFA enrollment reports
- Authentication method statistics
- Failed MFA attempt logs

### 3.5 Incident Response Family

#### IR.L2-3.6.1 - Incident Handling Capability
**Implementation Status**: Implemented
**Control Implementation Description**:
- 24/7 SOC with defined runbooks
- n8n automated response workflows
- Integration with PagerDuty for alerting
- Forensic toolkit deployment ready

**Evidence**:
- Incident response procedures
- Runbook library
- Incident tickets and timelines
- Post-incident reviews

### 3.6 Risk Assessment Family

#### RA.L2-3.11.1 - Risk Assessments
**Implementation Status**: Implemented
**Control Implementation Description**:
- Annual formal risk assessments
- Continuous vulnerability scanning
- Threat intelligence integration
- Risk scoring and prioritization matrix

**Evidence**:
- Risk assessment reports
- Vulnerability scan results
- Threat intelligence feeds
- Risk register updates

### 3.7 Security Assessment Family

#### CA.L2-3.12.1 - Security Control Assessments
**Implementation Status**: Implemented
**Control Implementation Description**:
- Annual third-party assessments
- Continuous automated testing
- Penetration testing quarterly
- Control effectiveness metrics

**Evidence**:
- Assessment reports
- Penetration test results
- Control test outputs
- Effectiveness KPIs

### 3.8 System and Communications Protection Family

#### SC.L2-3.13.1 - Boundary Protection
**Implementation Status**: Implemented
**Control Implementation Description**:
- Cloud Armor DDoS protection
- WAF with OWASP rules
- Network segmentation via VPCs
- Intrusion detection/prevention

**Evidence**:
- Network diagrams
- Firewall rule exports
- IDS/IPS alerts
- WAF block logs

#### SC.L2-3.13.8 - Implement Cryptography
**Implementation Status**: Implemented
**Control Implementation Description**:
- FIPS 140-2 validated modules
- TLS 1.3 for all external connections
- AES-256-GCM for data at rest
- Key management via Cloud KMS/HSM

**Evidence**:
- FIPS certificates
- TLS configuration scans
- Encryption inventory
- Key rotation logs

### 3.9 System and Information Integrity Family

#### SI.L2-3.14.1 - Flaw Remediation
**Implementation Status**: Implemented
**Control Implementation Description**:
- Automated vulnerability scanning
- Patch management via Ansible
- Zero-day response procedures
- Mean time to remediation tracking

**Evidence**:
- Patch deployment logs
- Vulnerability closure reports
- MTTR metrics
- Emergency patch records

---

## 4. CONTROL SUMMARY TABLE

| Control ID | Control Name | Implementation Status | POA&M Item |
|------------|--------------|----------------------|------------|
| AC.L2-3.1.1 | Limit System Access | Implemented | None |
| AC.L2-3.1.2 | Limit Transaction Functions | Implemented | None |
| AC.L2-3.1.3 | Control CUI Flow | Implemented | None |
| AC.L2-3.1.5 | Employ Least Privilege | Implemented | None |
| AC.L2-3.1.6 | Non-privileged Accounts | Implemented | None |
| AC.L2-3.1.7 | Prevent Non-privileged Execution | Implemented | None |
| AC.L2-3.1.12 | Monitor Remote Access | Implemented | None |
| AC.L2-3.1.20 | External System Connections | Partially Implemented | POA&M-001 |
| AC.L2-3.1.21 | Portable Storage Control | Planned | POA&M-002 |
| AU.L2-3.3.1 | System Audit Records | Implemented | None |
| AU.L2-3.3.2 | Review/Update Logged Events | Implemented | None |
| AU.L2-3.3.4 | Audit Failure Alerts | Implemented | None |
| AU.L2-3.3.5 | Correlate Audit Trails | Implemented | None |
| AU.L2-3.3.6 | Time Synchronization | Implemented | None |
| AU.L2-3.3.8 | Protect Audit Information | Implemented | None |
| CM.L2-3.4.1 | Baseline Configurations | Implemented | None |
| CM.L2-3.4.2 | Security Configuration Settings | Implemented | None |
| CM.L2-3.4.3 | Track/Control Changes | Implemented | None |
| CM.L2-3.4.4 | Analyze Security Impact | Implemented | None |
| CM.L2-3.4.5 | Access Restrictions for Change | Implemented | None |
| CM.L2-3.4.6 | Least Functionality | Implemented | None |
| CM.L2-3.4.7 | Restrict Programs | Implemented | None |
| CM.L2-3.4.8 | Allowlist Applications | Partially Implemented | POA&M-003 |
| CM.L2-3.4.9 | User-installed Software | Planned | POA&M-004 |
| IA.L2-3.5.3 | Multifactor Authentication | Implemented | None |
| IA.L2-3.5.4 | Unique Identifiers | Implemented | None |
| IA.L2-3.5.5 | Prevent Identifier Reuse | Implemented | None |
| IA.L2-3.5.6 | Disable After Inactivity | Implemented | None |
| IA.L2-3.5.10 | Store/Transmit Passwords | Implemented | None |
| IR.L2-3.6.1 | Incident Handling Capability | Implemented | None |
| IR.L2-3.6.2 | Track/Document Incidents | Implemented | None |
| IR.L2-3.6.3 | Test Incident Response | Partially Implemented | POA&M-005 |
| RA.L2-3.11.1 | Risk Assessments | Implemented | None |
| RA.L2-3.11.2 | Scan for Vulnerabilities | Implemented | None |
| RA.L2-3.11.3 | Remediate Vulnerabilities | Implemented | None |
| CA.L2-3.12.1 | Security Control Assessments | Implemented | None |
| CA.L2-3.12.2 | Plans of Action | Implemented | None |
| CA.L2-3.12.3 | Monitor Controls | Implemented | None |
| CA.L2-3.12.4 | System Security Plans | Implemented | None |
| SC.L2-3.13.1 | Boundary Protection | Implemented | None |
| SC.L2-3.13.2 | Secure Engineering | Implemented | None |
| SC.L2-3.13.5 | Public-access Systems | Implemented | None |
| SC.L2-3.13.8 | Implement Cryptography | Implemented | None |
| SC.L2-3.13.11 | CUI Encryption at Rest | Implemented | None |
| SC.L2-3.13.16 | CUI Encryption in Transit | Implemented | None |
| SI.L2-3.14.1 | Flaw Remediation | Implemented | None |
| SI.L2-3.14.2 | Malicious Code Protection | Implemented | None |
| SI.L2-3.14.3 | Security Alerts/Advisories | Implemented | None |
| SI.L2-3.14.4 | Update Malicious Code Protection | Implemented | None |
| SI.L2-3.14.5 | System Monitoring | Implemented | None |
| SI.L2-3.14.6 | Monitor Security Alerts | Implemented | None |
| SI.L2-3.14.7 | Identify Unauthorized Use | Implemented | None |

**Summary**:
- Total Controls: 110
- Implemented: 103 (93.6%)
- Partially Implemented: 3 (2.7%)
- Planned: 4 (3.6%)

---

## 5. PLAN OF ACTION & MILESTONES (POA&M)

| POA&M ID | Control | Weakness | Scheduled Completion | Resources Required |
|----------|---------|----------|---------------------|-------------------|
| POA&M-001 | AC.L2-3.1.20 | Incomplete external connection inventory | 2025-03-31 | 40 hours, network scanner |
| POA&M-002 | AC.L2-3.1.21 | No USB device control | 2025-04-30 | 80 hours, endpoint agent |
| POA&M-003 | CM.L2-3.4.8 | Application allowlisting partial | 2025-02-28 | 60 hours, AppLocker config |
| POA&M-004 | CM.L2-3.4.9 | User software installation control | 2025-05-31 | 100 hours, GPO deployment |
| POA&M-005 | IR.L2-3.6.3 | Incident response testing gaps | 2025-03-15 | 20 hours, tabletop exercise |

---

## 6. APPENDICES

### Appendix A: System Architecture Diagrams
[Reference: ARCHITECTURE_DESIGN.md]

### Appendix B: Network Topology
[Reference: Network segmentation diagrams]

### Appendix C: Data Flow Diagrams
[Reference: DFD documentation]

### Appendix D: Hardware and Software Inventory
[Reference: Asset inventory export]

### Appendix E: Ports, Protocols, and Services
| Service | Port | Protocol | Purpose | Encryption |
|---------|------|----------|---------|------------|
| Gitea Web | 443 | HTTPS | Web interface | TLS 1.3 |
| Gitea SSH | 22 | SSH | Git operations | SSH-2 |
| Prometheus | 9090 | HTTP | Metrics | Internal only |
| Grafana | 3000 | HTTPS | Dashboards | TLS 1.3 |
| n8n | 5678 | HTTPS | Workflows | TLS 1.3 |

### Appendix F: Interconnection Security Agreements
[Reference: ISA documentation]

### Appendix G: Incident Response Plan
[Reference: IR procedures]

### Appendix H: Contingency Plan
[Reference: Disaster recovery documentation]

### Appendix I: Configuration Management Plan
[Reference: CM procedures]

### Appendix J: Security Control Testing
[Reference: Control test results]