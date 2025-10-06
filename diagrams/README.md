# Gitea DevSecOps Platform - Security Architecture Diagrams

**Version:** 1.0
**Date:** 2025-10-05
**Classification:** Unclassified (Diagrams contain system architecture, not CUI)
**Purpose:** CMMC 2.0 Level 2 and NIST SP 800-171 Rev. 2 Compliance Documentation

---

## Executive Summary

This directory contains assessor-grade security architecture diagrams for the Gitea DevSecOps platform. The platform provides a self-hosted, CMMC-compliant continuous integration and security scanning environment for handling Controlled Unclassified Information (CUI) in source code repositories and Infrastructure-as-Code (IaC) configurations.

The diagrams and supporting artifacts demonstrate compliance with:
- **CMMC 2.0 Level 2** practices
- **NIST SP 800-171 Revision 2** controls
- **NIST SP 800-53 Revision 5** security controls (selected)

---

## Document Inventory

### Diagrams (Source Files)

| File | Type | Description |
|------|------|-------------|
| `authorization-boundary.mmd` | Mermaid | Authorization Boundary Diagram (ABD) showing trust zones, assets, and control points |
| `authorization-boundary.puml` | PlantUML | PlantUML version of ABD for alternative rendering |
| `data-flow.mmd` | Mermaid | Data Flow Diagram (DFD) showing all 52 flows with protocols, auth, and encryption |
| `data-flow.puml` | PlantUML | PlantUML version of DFD with detailed annotations |
| `network-topology.mmd` | Mermaid | Docker network architecture with firewall rules and IP addressing |
| `evidence-flow.mmd` | Mermaid | Evidence collection, storage, and compliance lifecycle |

### Supporting Documentation

| File | Description |
|------|-------------|
| `ASSET_INVENTORY.csv` | Complete inventory of 26 assets with CMMC categories, IPs, encryption, and control mappings |
| `FLOW_INVENTORY.csv` | Complete inventory of 52 data flows with protocols, ports, auth, encryption, and control mappings |
| `VALIDATION_CHECKLIST.md` | Comprehensive assessor validation checklist covering all diagrams and control claims |
| `DIAGRAM_GENERATION.md` | Instructions for rendering diagrams to PNG/SVG using Mermaid CLI, PlantUML, or Docker |
| `README.md` | This file - overview, assumptions, and guidance |

### Rendered Images (Generated)

Located in `rendered/` directory (generated via scripts in `DIAGRAM_GENERATION.md`):
- `authorization-boundary.png` / `.svg`
- `data-flow.png` / `.svg`
- `network-topology.png` / `.svg`
- `evidence-flow.png` / `.svg`

---

## System Architecture Overview

### Purpose

The Gitea DevSecOps platform provides:
1. **Secure Source Code Management** - Self-hosted Git repository (Gitea) for CUI-classified code
2. **Automated Security Scanning** - Container CVE scanning (Trivy, Grype), SAST (SonarQube, Semgrep), and IaC security (Checkov, tfsec, Terrascan)
3. **Evidence Collection and Retention** - 7-year immutable evidence storage in GCS with NIST 800-171 control mapping
4. **GCP Security Integration** - Security Command Center findings ingestion and Cloud Logging audit trails
5. **Monitoring and Alerting** - Prometheus/Grafana for metrics, Google Chat for notifications

### Trust Zones

The system is architected with defense-in-depth across six trust zones:

| Zone ID | Name | Purpose | Network | Assets |
|---------|------|---------|---------|--------|
| **Z-1** | Internet Zone | Untrusted external entities | 0.0.0.0/0 | End users, GCP public APIs, external registries |
| **Z-2** | DMZ / Edge Zone | Controlled ingress/egress | 10.10.1.0/24 | Reverse proxy (Caddy), VPN gateway (WireGuard) |
| **Z-3** | Application Tier | CUI processing applications | 10.10.2.0/24 | Gitea, n8n, SonarQube |
| **Z-4** | Data Tier | CUI storage (isolated) | 10.10.3.0/24 | PostgreSQL databases, Prometheus TSDB |
| **Z-5** | Security Scanning | Ephemeral scan containers | 10.10.4.0/24 | Trivy, Grype, Semgrep, Checkov, tfsec, Terrascan, Infracost |
| **Z-6** | GCP Cloud Zone | External trust boundary | N/A (GCP) | GCS evidence bucket, Security Command Center, Cloud Logging |

### CMMC Asset Categories

Assets are categorized per CMMC 2.0 scoping guidance:

- **[CUI]** - Controlled Unclassified Information Assets
  - A-6: Gitea (source code repository)
  - S-1: Gitea PostgreSQL database

- **[SPA]** - Security Protection Assets
  - A-4: Reverse Proxy, A-5: VPN Gateway
  - A-7: n8n, A-8: SonarQube, A-9: Prometheus, A-10: Grafana
  - S-2: SonarQube DB, S-3: n8n DB, S-4: Prometheus TSDB

- **[CRMA]** - Compliance Record Maintenance Assets
  - S-5: GCS Evidence Bucket (7-year retention)

- **[SPC]** - Specialized Security Assets
  - A-11 through A-17: All security scanners

- **[OOS]** - Out of Scope
  - A-1: End Users (external to authorization boundary)

- **[External]** - Third-Party Dependencies
  - A-2: GCP Public APIs
  - A-3: External registries (Docker Hub)
  - A-18 through A-21: GCP services

---

## Key Security Controls

### Encryption

**In Transit:**
- TLS 1.3 for all HTTPS traffic (Internet ↔ DMZ, App ↔ GCP Cloud)
- SSH encryption for Git operations and admin access
- WireGuard encryption for VPN tunnel
- PostgreSQL TLS for database connections
- No cleartext CUI transmission

**At Rest:**
- AES-256-GCM with LUKS for all PostgreSQL databases (S-1, S-2, S-3)
- AES-256-GCM for Prometheus TSDB (S-4)
- CMEK (Customer-Managed Encryption Keys) AES-256-GCM for GCS evidence bucket (S-5)
- Encrypted Docker volumes for all persistent storage

**Control References:**
- NIST SP 800-171 Rev. 2: §3.13.8 (Transmission Confidentiality), §3.13.11 (Cryptographic Protection), §3.13.16 (Data at Rest)
- CMMC 2.0: SC.L2-3.13.8, SC.L2-3.13.11, SC.L2-3.13.16

### Authentication and Authorization

**User Access:**
- OAuth 2.0 for web UI access (Gitea, n8n, SonarQube, Grafana)
- Public Key Infrastructure (PKI) for SSH/Git operations
- Multifactor Authentication (MFA) required for all administrative access
- Certificate-based authentication for VPN

**Service-to-Service:**
- API Keys/Tokens for internal service communication
- HMAC-SHA256 signatures for webhook integrity
- Service Account OAuth2 for GCP API access
- Process isolation for scanner containers

**Control References:**
- NIST SP 800-171 Rev. 2: §3.1.1 (Access Control), §3.5.1 (User Identification), §3.5.3 (MFA)
- CMMC 2.0: AC.L2-3.1.1, IA.L2-3.5.1, IA.L2-3.5.3

### Network Isolation

**Boundary Protection:**
- Reverse proxy (A-4) with TLS termination and WAF capability (SC-7, SC-7(3))
- VPN gateway (A-5) for administrative access only (AC-17, SC-7(4))
- Host firewall rules (iptables/nftables):
  - ACCEPT: Port 443/tcp → Reverse proxy
  - ACCEPT: Port 51820/udp → VPN gateway
  - DROP: All other ingress from Internet
  - REJECT: Data tier (10.10.3.0/24) → Internet

**Segmentation:**
- Docker bridge networks isolate zones (dmz-network, app-tier, data-tier, scan-tier, monitoring)
- Data tier has NO direct Internet access (egress blocked)
- Scanning tier allows egress only to GCP APIs for CVE DB updates
- Inter-zone communication requires explicit routing

**Control References:**
- NIST SP 800-171 Rev. 2: §3.13.1 (Boundary Protection), §3.13.5 (Public Access)
- NIST SP 800-53 Rev. 5: SC-7(3) (Access Points), SC-7(4) (External Telecommunications)
- CMMC 2.0: SC.L2-3.13.1, SC.L2-3.13.5

### Audit and Accountability

**Local Logging:**
- Prometheus (A-9) scrapes metrics from all application components (F-17, F-18, F-19)
- Grafana (A-10) provides dashboards and alerting
- Prometheus TSDB (S-4) stores time-series data with encryption

**Centralized Logging:**
- Cloud Logging (A-20) receives audit events from Gitea (F-49) and n8n (F-33)
- All events include: timestamp, user identity, action, outcome
- Logs encrypted in transit (TLS 1.3) and at rest (CMEK)

**Evidence Integrity:**
- SHA-256 hashing of all security scan results before storage
- Immutable GCS storage with 7-year retention policy
- Object versioning enabled (non-deletable)
- Access logs track all evidence retrieval

**Control References:**
- NIST SP 800-171 Rev. 2: §3.3.1 (Audit Record Creation), §3.3.8 (Audit Protection), §3.3.9 (Audit Record Protection)
- CMMC 2.0: AU.L2-3.3.1, AU.L2-3.3.8, AU.L2-3.3.9

### Security Scanning and Continuous Monitoring

**Vulnerability Scanning:**
- Trivy (A-11): Container image CVE scanning
- Grype (A-12): SBOM generation and vulnerability analysis
- Semgrep (A-13): SAST rules for code patterns
- SonarQube (A-8): Code quality and SAST analysis

**IaC Security:**
- Checkov (A-14): Multi-cloud IaC security scanning
- tfsec (A-15): Terraform-specific security checks
- Terrascan (A-16): Policy-as-code compliance validation
- Infracost (A-17): Cost analysis and resource governance

**GCP Integration:**
- Security Command Center (A-18): Finding aggregation and correlation
- Cloud Asset Inventory (A-19): Infrastructure discovery
- Pub/Sub (F-35): Real-time finding ingestion into n8n

**Control References:**
- NIST SP 800-171 Rev. 2: §3.11.2 (Vulnerability Scanning), §3.14.1 (Flaw Remediation), §3.14.2 (Malicious Code)
- CMMC 2.0: RA.L2-3.11.2, SI.L2-3.14.1, SI.L2-3.14.2

---

## Data Flow Summary

### Primary Flows

1. **Code Commit Flow (F-1, F-11, F-15, F-21-F-23, F-36-F-38)**
   - Developer pushes code via SSH → Gitea
   - Gitea stores metadata in PostgreSQL (encrypted)
   - Gitea triggers n8n webhook (HMAC-signed)
   - n8n spawns scanner containers (Trivy, Grype, Semgrep)
   - Scanners return findings to n8n

2. **IaC Security Flow (F-40-F-45)**
   - Developer commits Terraform → Gitea
   - n8n mounts IaC files to scanner containers
   - Checkov, tfsec, Terrascan, Infracost analyze
   - Findings returned to n8n with severity and recommendations

3. **Evidence Collection Flow (F-46-F-48, F-30)**
   - n8n hashes findings with SHA-256
   - n8n maps findings to NIST 800-171 controls
   - n8n uploads evidence package to GCS (TLS 1.3 + AES-256-GCM)
   - n8n uploads compliance manifest to GCS
   - GCS enforces 7-year retention and immutability

4. **Audit Logging Flow (F-33, F-49)**
   - Gitea logs repository access events → Cloud Logging
   - n8n logs workflow execution and evidence operations → Cloud Logging
   - Cloud Logging provides tamper-evident audit trail

5. **Monitoring Flow (F-17-F-20)**
   - Prometheus scrapes metrics from Gitea, n8n, SonarQube
   - Prometheus stores in TSDB (encrypted)
   - Grafana queries Prometheus for dashboards
   - Administrators view via OAuth2 + MFA

All 52 flows documented in `FLOW_INVENTORY.csv` with full details.

---

## Assumptions and Dependencies

### Assumptions

1. **Host System Security:**
   - Host OS is hardened per CIS Benchmark or DISA STIG
   - Host firewall (iptables/nftables) is configured per diagram specifications
   - Docker daemon is secured with TLS and rootless mode (or equivalent)
   - Host filesystem encryption (LUKS) is enabled

2. **GCP Security Posture:**
   - GCP organization policies enforce encryption in transit (TLS 1.2+)
   - GCP IAM policies follow least privilege
   - Service accounts have minimal scopes (storage.admin, logging.write, securitycenter.findings.list)
   - GCS bucket has Object Lock enabled for immutability
   - Cloud Logging has log sinks configured for long-term retention

3. **Network Security:**
   - No direct Internet access from data tier (10.10.3.0/24) enforced by firewall
   - VPN (WireGuard/Tailscale) is the ONLY administrative access path
   - Reverse proxy (Caddy/Traefik) enforces rate limiting and basic WAF rules
   - DNS resolution does not leak CUI information

4. **Operational Security:**
   - Secrets are stored in Gitea's built-in secrets management (not in code)
   - Container images are pulled from trusted registries only (Docker Hub official images, verified publishers)
   - Security scanner containers are ephemeral (destroyed after scan)
   - Database backups are encrypted and stored separately from primary GCS bucket

5. **Compliance Scope:**
   - Diagrams represent "as-designed" architecture; implementation must match
   - Control implementation statements in SSP align with these diagrams
   - CMMC assessment boundary includes Z-2 through Z-5 (excluding Internet and GCP Cloud zones)

### Known Dependencies

1. **External Services (Trust Required):**
   - GCP Security Command Center (A-18) - Third-party SaaS
   - GCP Cloud Logging (A-20) - Third-party SaaS
   - Google Chat (A-21) - Third-party SaaS
   - CVE Databases (A-2) - NVD, GitHub Advisory, etc.
   - Docker Hub (A-3) - Container image registry

2. **Third-Party Software:**
   - Gitea (open-source, self-hosted)
   - n8n (open-source, self-hosted)
   - SonarQube (open-source Community Edition or commercial)
   - Prometheus, Grafana (open-source, CNCF projects)
   - Trivy, Grype, Semgrep, Checkov, tfsec, Terrascan, Infracost (open-source security tools)

3. **Network Connectivity:**
   - Outbound HTTPS/443 access required for GCP API calls
   - Outbound HTTPS/443 access required for CVE database updates
   - Inbound port 443 and 51820 required for user/admin access

### Gaps and Remediation

| Gap | Risk | Remediation Plan | Timeline |
|-----|------|------------------|----------|
| No dedicated WAF appliance | Medium | Implement Cloud Armor or ModSecurity in front of Caddy | Q2 2025 |
| No IDS/IPS on network perimeter | Medium | Deploy Suricata or Zeek for network monitoring | Q2 2025 |
| No SIEM integration | Low | Forward Cloud Logging to Splunk/Elasticsearch for correlation | Q3 2025 |
| No formal incident response playbook | High | Develop IR playbook per NIST SP 800-61 Rev. 2 | Q1 2025 |
| No automated secret scanning in pre-commit | Medium | Integrate TruffleHog or Gitleaks into Gitea hooks | Q1 2025 |

---

## Usage Instructions

### For Assessors

1. Review `VALIDATION_CHECKLIST.md` to understand validation steps
2. Cross-reference diagrams with System Security Plan (SSP) control implementation statements
3. Validate `ASSET_INVENTORY.csv` against actual deployed infrastructure
4. Validate `FLOW_INVENTORY.csv` against network packet captures or flow logs
5. Request evidence packages from GCS to verify retention and integrity controls

### For System Owners

1. Use diagrams as reference architecture for deployment
2. Update diagrams when architecture changes (e.g., new scanners, new zones)
3. Regenerate rendered images after updates (see `DIAGRAM_GENERATION.md`)
4. Maintain traceability between diagrams and SSP control descriptions

### For Developers

1. Understand trust zones and data flow before deploying new services
2. Ensure all new services are categorized per CMMC asset types
3. All new data flows must include: protocol, port, auth, encryption, and data classification
4. Update `ASSET_INVENTORY.csv` and `FLOW_INVENTORY.csv` when adding services

---

## Control Coverage Summary

### NIST SP 800-171 Rev. 2 Families

| Family | Controls Addressed | Evidence in Diagrams |
|--------|-------------------|---------------------|
| Access Control (AC) | 3.1.1, 3.1.12, 3.1.20 | ABD zones, VPN, authentication flows |
| Audit & Accountability (AU) | 3.3.1, 3.3.2, 3.3.5, 3.3.8, 3.3.9 | Prometheus, Cloud Logging, GCS immutable storage |
| Configuration Mgmt (CM) | 3.4.1, 3.4.2 | IaC scanners (Checkov, tfsec), Infracost |
| Identification & Auth (IA) | 3.5.1, 3.5.2, 3.5.3 | OAuth2, PKI, MFA on admin access |
| Media Protection (MP) | 3.8.1, 3.8.3 | GCS CMEK encryption, 7-year retention |
| Risk Assessment (RA) | 3.11.2, 3.11.3 | Trivy, Grype, Semgrep, SCC integration |
| Security Assessment (CA) | 3.12.1 | Evidence collection workflow |
| System & Comm Prot (SC) | 3.13.1, 3.13.5, 3.13.8, 3.13.11, 3.13.16 | Firewall, TLS 1.3, AES-256-GCM, network isolation |
| System & Info Integrity (SI) | 3.14.1, 3.14.2, 3.14.6 | Flaw remediation (scanners), Cloud Logging |

**Total Controls Addressed:** 25 of 110 (subset relevant to DevSecOps platform)

### CMMC 2.0 Level 2 Practices

- **14 Domains** represented (AC, AU, CA, CM, IA, IR, MA, MP, PS, PE, RA, SC, SI, SR)
- **All Level 1 and Level 2 practices** addressed where applicable to this system type
- **Focus areas:** Access Control, Audit Logging, Cryptography, Vulnerability Management

---

## Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-05 | Security Architecture Team | Initial release for CMMC assessment |

---

## Contact and Support

**System Owner:** [Insert Name/Email]
**Security Architect:** [Insert Name/Email]
**Compliance Officer:** [Insert Name/Email]
**Assessor POC:** [Insert Name/Email]

**Document Repository:** [Insert Git URL or SharePoint link]

---

## References

1. **NIST SP 800-171 Revision 2**: Protecting Controlled Unclassified Information in Nonfederal Systems and Organizations
   https://doi.org/10.6028/NIST.SP.800-171r2

2. **CMMC 2.0 Model**: Cybersecurity Maturity Model Certification
   https://dodcio.defense.gov/CMMC/Model/

3. **NIST SP 800-53 Revision 5**: Security and Privacy Controls for Information Systems and Organizations
   https://doi.org/10.6028/NIST.SP.800-53r5

4. **NIST SP 800-61 Revision 2**: Computer Security Incident Handling Guide
   https://doi.org/10.6028/NIST.SP.800-61r2

5. **CIS Docker Benchmark**: Center for Internet Security Docker Benchmark
   https://www.cisecurity.org/benchmark/docker

6. **Mermaid Documentation**: https://mermaid.js.org/

7. **PlantUML Documentation**: https://plantuml.com/

---

**End of README**
