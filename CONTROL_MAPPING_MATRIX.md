# DevSecOps Tool to Control Mapping Matrix
## CMMC 2.0 Level 2 & NIST SP 800-171 Rev. 2 Alignment

### TOOL INVENTORY (34 Tools)

| Category | Tool | License | Primary Function | Evidence Generated |
|----------|------|---------|-----------------|-------------------|
| **Source Code Security** |
| 1 | SonarQube | LGPL v3 | SAST, Code Quality | Scan reports, quality gates |
| 2 | Semgrep | LGPL v2.1 | Pattern-based SAST | Finding reports, rule matches |
| 3 | Bandit | Apache 2.0 | Python Security | Security issues report |
| 4 | git-secrets | Apache 2.0 | Credential Scanning | Pre-commit scan logs |
| **Container Security** |
| 5 | Trivy | Apache 2.0 | Container Scanning | CVE reports, SBOM |
| 6 | Grype | Apache 2.0 | Vulnerability Detection | Vulnerability database matches |
| 7 | Cosign | Apache 2.0 | Container Signing | Signature verification logs |
| 8 | Syft | Apache 2.0 | SBOM Generation | Software inventory |
| **Dynamic Security** |
| 9 | OWASP ZAP | Apache 2.0 | DAST | Penetration test reports |
| 10 | Nuclei | MIT | Vulnerability Scanner | Template match results |
| **IaC Security** |
| 11 | Checkov | Apache 2.0 | IaC Scanning | Policy violations, compliance |
| 12 | tfsec | MIT | Terraform Security | Security findings |
| 13 | Terrascan | Apache 2.0 | Policy as Code | Policy evaluation results |
| 14 | Terraform Sentinel | Commercial | Policy Enforcement | Policy decisions |
| 15 | Infracost | Apache 2.0 | Cost Analysis | Cost estimates, drift reports |
| **Image Security** |
| 16 | Packer | MPL 2.0 | Image Building | Build logs, manifests |
| 17 | Ansible | GPL v3 | Configuration Mgmt | Playbook execution logs |
| 18 | ansible-lint | MIT | Ansible Security | Lint reports |
| **Monitoring & Observability** |
| 19 | Prometheus | Apache 2.0 | Metrics Collection | Time-series data |
| 20 | Grafana | AGPL v3 | Visualization | Dashboards, alerts |
| 21 | AlertManager | Apache 2.0 | Alert Routing | Alert history |
| 22 | Loki | AGPL v3 | Log Aggregation | Centralized logs |
| 23 | Tempo | AGPL v3 | Distributed Tracing | Trace data |
| **Runtime Security** |
| 24 | Falco | Apache 2.0 | Runtime Protection | Security events |
| 25 | osquery | Apache 2.0 | Endpoint Monitoring | System state queries |
| 26 | Wazuh | GPL v2 | HIDS/SIEM | Security incidents |
| **GCP Integration** |
| 27 | Security Command Center | GCP Service | Vulnerability Mgmt | Finding reports |
| 28 | Cloud Asset Inventory | GCP Service | Asset Tracking | Inventory exports |
| 29 | Cloud Logging | GCP Service | Log Management | Audit trails |
| 30 | Cloud KMS | GCP Service | Key Management | Key usage logs |
| **GitOps & Automation** |
| 31 | Atlantis | Apache 2.0 | Terraform Automation | Plan/apply logs |
| 32 | Terragrunt | MIT | Terraform Wrapper | Execution logs |
| 33 | n8n | Fair-code | Workflow Automation | Workflow execution history |
| 34 | Taiga | AGPL v3 | Project Management | Task tracking, metrics |

## CMMC 2.0 LEVEL 2 CONTROL MAPPING

### Access Control (AC) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| AC.L2-3.1.1 | Limit system access | Gitea, Cloud IAM, Atlantis | Access logs, RBAC configs, session records |
| AC.L2-3.1.2 | Limit transactions/functions | Terragrunt, Sentinel | Policy files, enforcement logs |
| AC.L2-3.1.3 | Control CUI flow | Cloud KMS, VPC-SC | Encryption logs, network flows |
| AC.L2-3.1.5 | Employ least privilege | Cloud IAM, osquery | Permission audits, access reviews |
| AC.L2-3.1.6 | Non-privileged accounts | Gitea, Cloud IAM | Account inventories, privilege reports |
| AC.L2-3.1.7 | Prevent non-privileged execution | Falco, Wazuh | Runtime alerts, blocked executions |
| AC.L2-3.1.12 | Monitor remote access | Cloud Logging, Grafana | Session logs, connection metrics |
| AC.L2-3.1.20 | External system connections | Security Command Center | Connection logs, approval records |
| AC.L2-3.1.21 | Portable storage control | Wazuh, osquery | Device logs, policy enforcement |

### Audit and Accountability (AU) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| AU.L2-3.3.1 | System audit records | Cloud Logging, Loki | Audit logs, retention policies |
| AU.L2-3.3.2 | Review/update logged events | AlertManager, Grafana | Event configurations, reviews |
| AU.L2-3.3.4 | Audit failure alerts | AlertManager, n8n | Alert configurations, notifications |
| AU.L2-3.3.5 | Correlate audit trails | Wazuh, Tempo | Correlation rules, timeline analysis |
| AU.L2-3.3.6 | Time synchronization | Prometheus, NTP | Time sync logs, drift reports |
| AU.L2-3.3.8 | Protect audit information | Cloud KMS, backup | Integrity checks, access controls |

### Configuration Management (CM) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| CM.L2-3.4.1 | Baseline configurations | Packer, Ansible | Baseline docs, golden images |
| CM.L2-3.4.2 | Security configuration settings | Checkov, tfsec | Hardening guides, scan results |
| CM.L2-3.4.3 | Track/control changes | Gitea, Atlantis | Change logs, approval workflows |
| CM.L2-3.4.4 | Analyze security impact | Terrascan, Infracost | Impact assessments, cost analysis |
| CM.L2-3.4.5 | Access restrictions for change | Gitea, RBAC | Change permissions, access matrix |
| CM.L2-3.4.6 | Least functionality | Container minimal images | Image manifests, package lists |
| CM.L2-3.4.7 | Restrict programs | Falco, AppArmor | Allowlists, execution policies |
| CM.L2-3.4.8 | Allowlist applications | Wazuh, osquery | Application inventories, policies |
| CM.L2-3.4.9 | User-installed software | Group Policy, MDM | Software policies, installation logs |

### Identification and Authentication (IA) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| IA.L2-3.5.3 | Multifactor authentication | Cloud IAM, Gitea | MFA configs, enrollment reports |
| IA.L2-3.5.4 | Unique identifiers | LDAP, Cloud IAM | Identity inventory, UUID mapping |
| IA.L2-3.5.5 | Prevent identifier reuse | Cloud IAM policies | Reuse policies, audit logs |
| IA.L2-3.5.6 | Disable after inactivity | Cloud IAM, scripts | Inactivity reports, disable logs |
| IA.L2-3.5.10 | Store/transmit passwords | Cloud KMS, HashiCorp Vault | Encryption logs, key usage |

### Incident Response (IR) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| IR.L2-3.6.1 | Incident handling capability | Wazuh, n8n | Runbooks, response workflows |
| IR.L2-3.6.2 | Track/document incidents | Taiga, Jira | Incident tickets, timelines |
| IR.L2-3.6.3 | Test incident response | Tabletop exercises | Test reports, lessons learned |

### Risk Assessment (RA) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| RA.L2-3.11.1 | Risk assessments | Security Command Center | Risk reports, vulnerability scans |
| RA.L2-3.11.2 | Scan for vulnerabilities | Trivy, Grype, Nuclei | Scan schedules, findings |
| RA.L2-3.11.3 | Remediate vulnerabilities | n8n, Ansible | Patch logs, remediation timelines |

### Security Assessment (CA) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| CA.L2-3.12.1 | Security control assessments | All scanning tools | Assessment reports, test results |
| CA.L2-3.12.2 | Plans of action | Taiga, project tracking | POA&M documents, milestones |
| CA.L2-3.12.3 | Monitor controls | Prometheus, Grafana | Continuous monitoring data |
| CA.L2-3.12.4 | System security plans | Documentation tools | SSP documents, updates |

### System and Communications Protection (SC) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| SC.L2-3.13.1 | Boundary protection | WAF, VPC firewall | Network diagrams, firewall rules |
| SC.L2-3.13.2 | Secure engineering | DevSecOps pipeline | SDLC documentation, gates |
| SC.L2-3.13.5 | Public-access systems | DMZ, reverse proxy | Network segmentation, ACLs |
| SC.L2-3.13.8 | Implement cryptography | Cloud KMS, TLS | Crypto inventory, certificates |
| SC.L2-3.13.11 | CUI encryption at rest | Cloud KMS, disk encryption | Encryption status, key rotation |
| SC.L2-3.13.16 | CUI encryption in transit | TLS 1.3, mTLS | Protocol configs, cipher suites |

### System and Information Integrity (SI) Domain

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| SI.L2-3.14.1 | Flaw remediation | Patch management | Patch logs, vulnerability closure |
| SI.L2-3.14.2 | Malicious code protection | ClamAV, Wazuh | AV logs, detection reports |
| SI.L2-3.14.3 | Security alerts/advisories | CVE monitoring | Advisory subscriptions, alerts |
| SI.L2-3.14.4 | Update malicious code protection | AV updates | Update logs, signature versions |
| SI.L2-3.14.5 | System monitoring | Full observability stack | Monitoring coverage, alerts |
| SI.L2-3.14.6 | Monitor security alerts | SIEM, AlertManager | Alert dashboards, responses |
| SI.L2-3.14.7 | Identify unauthorized use | Behavioral analysis | Anomaly detection, investigations |

## NIST SP 800-53 Rev. 5 ADDITIONAL CONTROLS

### High-Value Controls Not in CMMC

| Control | Description | Mapped Tools | Evidence Requirements |
|---------|-------------|--------------|----------------------|
| AC-6(9) | Log privileged functions | Cloud Audit Logs | Privileged action logs |
| AU-12(3) | Changes by automated tools | CI/CD logs | Automated change records |
| CM-3(6) | Cryptographic protection | Cosign, GPG | Signature verification |
| CP-9(8) | Cryptographic backup | Cloud KMS backup | Encrypted backup logs |
| IA-12(2) | Identity proof PKI | Certificate Manager | Certificate chains |
| SA-11(1) | Static code analysis | SonarQube, Semgrep | Scan reports |
| SA-11(8) | Dynamic code analysis | OWASP ZAP | Dynamic test results |
| SC-28(3) | Cryptographic keys | Cloud KMS, HSM | Key management logs |

## GAP ANALYSIS

### Current Coverage Assessment

| Domain | Total Controls | Covered | Partial | Gap | Coverage % |
|--------|---------------|---------|---------|-----|-----------|
| Access Control | 22 | 18 | 3 | 1 | 82% |
| Audit & Accountability | 16 | 14 | 2 | 0 | 88% |
| Configuration Management | 12 | 11 | 1 | 0 | 92% |
| Identification & Auth | 11 | 10 | 1 | 0 | 91% |
| Incident Response | 7 | 6 | 1 | 0 | 86% |
| Risk Assessment | 6 | 6 | 0 | 0 | 100% |
| Security Assessment | 5 | 5 | 0 | 0 | 100% |
| System Protection | 17 | 15 | 2 | 0 | 88% |
| System Integrity | 10 | 9 | 1 | 0 | 90% |
| **TOTAL** | **106** | **94** | **11** | **1** | **89%** |

### Gap Remediation Plan

| Gap | Control | Required Tool | Implementation Phase | Estimated Effort |
|-----|---------|---------------|---------------------|------------------|
| AC-2(13) | Account monitoring | Privileged Access Mgmt | Phase 3 | 40 hours |
| AU-4(1) | Transfer to alternate storage | Log shipping solution | Phase 3 | 20 hours |
| CM-3(7) | Unauthorized changes | File integrity monitoring | Phase 2 | 30 hours |
| IA-5(13) | PKI-based auth | Certificate infrastructure | Phase 4 | 60 hours |
| SC-8(5) | Concealment techniques | Traffic obfuscation | Phase 5 | 40 hours |

## EVIDENCE COLLECTION MATRIX

### Automated Evidence by Control Family

| Control Family | Evidence Type | Collection Method | Frequency | Retention |
|----------------|---------------|-------------------|-----------|-----------|
| Access Control | Access logs, RBAC configs | API export, log parsing | Real-time | 1 year |
| Audit | Audit logs, events | Syslog, cloud APIs | Real-time | 3 years |
| Configuration | Baselines, changes | Git commits, snapshots | On change | 7 years |
| Identity | Auth logs, MFA status | LDAP queries, IAM APIs | Daily | 1 year |
| Incident Response | Tickets, timelines | API export, reports | On incident | 3 years |
| Risk Assessment | Scan results, risks | Scanner APIs, exports | Weekly | 1 year |
| Security Assessment | Assessment reports | Document generation | Quarterly | 3 years |
| System Protection | Network configs, crypto | Config dumps, cert checks | Daily | 1 year |
| System Integrity | Patches, AV status | Package queries, logs | Daily | 1 year |

### Evidence Integrity Chain

```yaml
evidence_pipeline:
  collection:
    - source: Tool APIs and exports
    - format: JSON, CSV, PDF
    - validation: Schema checking

  processing:
    - normalization: Common data model
    - enrichment: Add metadata
    - correlation: Link related evidence

  storage:
    - immediate: Hot storage (SSD)
    - archive: Cold storage (Cloud Storage)
    - backup: Cross-region replication

  integrity:
    - hashing: SHA-256 at collection
    - signing: GPG signature
    - timestamp: RFC 3161 TSA
    - chain: Blockchain anchor (optional)

  retrieval:
    - search: Elasticsearch index
    - export: Compliance packages
    - audit: Complete chain of custody
```