# SSDF-Compliant CI/CD Pipeline Architecture Diagrams

## Overview

This directory contains comprehensive architecture diagrams for the SSDF-compliant CI/CD pipeline implementation. All diagrams are available in multiple formats (Mermaid, PlantUML, ASCII) to support various use cases, from submission packages to text-only viewing.

**Branch**: `feature/ssdf-cicd-pipeline`
**Location**: `/home/notme/Desktop/gitea/ssdf/documentation/diagrams/`
**Created**: 2025-10-07
**NIST Framework**: SSDF v1.1 (NIST SP 800-218)

---

## Diagram Inventory

| Diagram | File | Size | Purpose | SSDF Coverage |
|---------|------|------|---------|---------------|
| **CI/CD Pipeline Architecture** | `CICD_PIPELINE_ARCHITECTURE.md` | 32 KB | Complete pipeline with 7 stages, security gates, and evidence collection | All 4 practice groups |
| **SSDF Practice Flow** | `SSDF_PRACTICE_FLOW.md` | 40 KB | Four-quadrant view of 47 practices with dependencies and tool mappings | PO, PS, PW, RV |
| **Evidence Collection Flow** | `EVIDENCE_COLLECTION_FLOW.md` | 59 KB | End-to-end evidence workflow from CI/CD to dashboard | PO.3, PO.4 |
| **Tool Integration Architecture** | `TOOL_INTEGRATION.md` | 42 KB | Network diagram of 34 tools with integration methods | All tools |
| **SSDF Compliance Coverage** | `COMPLIANCE_COVERAGE.md` | 33 KB | Heatmap of practice-to-tool coverage with gap analysis | 47 practices |
| **Attestation Generation Flow** | `ATTESTATION_FLOW.md` | 71 KB | SLSA provenance, Cosign signing, CISA form, and archival | PW.9, PS.3 |

**Total Documentation**: 277 KB across 6 comprehensive diagrams

---

## Quick Start

### Viewing Diagrams

#### 1. Mermaid (Recommended for Web)
```bash
# Install mermaid-cli
npm install -g @mermaid-js/mermaid-cli

# Render single diagram
mmdc -i CICD_PIPELINE_ARCHITECTURE.md -o cicd-pipeline.png -t dark -b transparent

# Render all diagrams
for file in *.md; do
  mmdc -i "$file" -o "${file%.md}.png" -t dark -b transparent -w 2400 -h 2400
done
```

#### 2. PlantUML (Recommended for Submission Packages)
```bash
# Using Docker (easiest)
docker run -v $(pwd):/data plantuml/plantuml -tpng /data/*.md

# Or install locally
wget https://github.com/plantuml/plantuml/releases/download/v1.2023.12/plantuml-1.2023.12.jar
java -jar plantuml.jar *.md
```

#### 3. ASCII (Terminal Viewing)
```bash
# View directly in terminal
less CICD_PIPELINE_ARCHITECTURE.md
# Scroll to "ASCII Diagram" section
```

---

## Diagram Details

### 1. CI/CD Pipeline Architecture

**File**: `CICD_PIPELINE_ARCHITECTURE.md`
**Formats**: Mermaid, PlantUML, ASCII
**Complexity**: 7 stages, 30+ tools, 15+ security gates

**Visualizes**:
- Pre-Commit Stage (PO.1, PS.1)
- PR Security Gate (PW.2, PW.6)
- Build Stage (PW.9, PS.3)
- Security Scanning (PW.7, RV.1)
- DAST Stage (PW.7, PW.8)
- Compliance & Evidence (PO.2, PO.3)
- Deployment (PW.8, RV.2)

**Key Features**:
- SSDF practice labels on every stage
- Evidence collection touchpoints
- Failure conditions and security gates
- Tool integration points
- Data flow between stages

**Use Cases**:
- Customer presentations
- Architecture reviews
- Security audits
- CISA attestation submissions

---

### 2. SSDF Practice Flow

**File**: `SSDF_PRACTICE_FLOW.md`
**Formats**: Mermaid, PlantUML (four-quadrant), ASCII
**Complexity**: 47 practices, 34 tools, 50+ dependencies

**Visualizes**:
- **Quadrant 1**: Prepare Organization (PO) - 12 practices
- **Quadrant 2**: Protect Software (PS) - 7 practices
- **Quadrant 3**: Produce Well-Secured Software (PW) - 19 practices
- **Quadrant 4**: Respond to Vulnerabilities (RV) - 9 practices

**Key Features**:
- Practice dependencies (solid arrows)
- Feedback loops (dashed arrows)
- Evidence flows (dotted arrows)
- Tool integration hub
- Sub-practice breakdowns

**Use Cases**:
- SSDF compliance roadmap
- Practice implementation planning
- Gap analysis and remediation
- Training and onboarding

---

### 3. Evidence Collection Flow

**File**: `EVIDENCE_COLLECTION_FLOW.md`
**Formats**: Mermaid sequence, PlantUML sequence, ASCII flow
**Complexity**: 25 steps, 10+ systems, 8 data formats

**Visualizes**:
1. CI/CD workflow execution
2. Tool output collection (JSON/XML/SARIF)
3. n8n workflow triggering
4. SHA-256 hash generation
5. Evidence manifest creation
6. GCS bucket upload (7-year retention)
7. PostgreSQL registry update
8. Google Chat notifications
9. Dashboard refresh
10. Complete audit trail

**Key Features**:
- Tool output formats (JSON, XML, SARIF, CycloneDX)
- Cryptographic verification (SHA-256)
- Storage architecture (GCS + PostgreSQL)
- Evidence manifest schema
- Integration methods

**Use Cases**:
- Evidence automation design
- Audit trail verification
- Integration troubleshooting
- Compliance documentation

---

### 4. Tool Integration Architecture

**File**: `TOOL_INTEGRATION.md`
**Formats**: Mermaid network, PlantUML component, ASCII network
**Complexity**: 34 tools, 6 integration methods, 100+ data flows

**Visualizes**:
- **Central Hub**: Gitea Actions Runner
- **SAST Tools**: SonarQube, Semgrep, Bandit, git-secrets
- **Container Tools**: Trivy, Grype, Syft, Cosign, Docker Bench
- **IaC Tools**: Checkov, tfsec, Terrascan, Atlantis, Terragrunt
- **DAST Tools**: OWASP ZAP, Nuclei, SSLyze
- **SCA Tools**: OSV-Scanner, Dependency Track, License Finder
- **Runtime Tools**: Falco, Wazuh, osquery
- **GCP Services**: SCC, KMS, Logging, Cloud Armor
- **Monitoring**: Prometheus, Grafana, Loki, Alertmanager
- **Automation**: n8n, HashiCorp Vault

**Key Features**:
- Integration methods (CLI, API, webhook, file I/O)
- Output formats by tool
- SSDF practice coverage per tool
- Authentication and authorization
- Network requirements and ports
- Performance characteristics

**Use Cases**:
- Tool selection and consolidation
- Integration planning
- Network architecture design
- Performance optimization

---

### 5. SSDF Compliance Coverage

**File**: `COMPLIANCE_COVERAGE.md`
**Formats**: Mermaid heatmap, ASCII matrix
**Complexity**: 47 practices × 34 tools = 1,598 mappings

**Visualizes**:
- Practice-to-tool coverage matrix
- Coverage status (Full 🟩, Partial 🟨, Gap 🟥)
- Group coverage percentages:
  - **PO**: 67% (8/12 implemented)
  - **PS**: 71% (5/7 implemented)
  - **PW**: 63% (12/19 implemented)
  - **RV**: 33% (3/9 implemented)
- **Overall**: 60% (28/47 practices)

**Key Features**:
- Detailed gap analysis
- Remediation roadmap (12-month)
- Tool utilization analysis
- Coverage improvement plan
- Machine-readable CSV export

**Gap Priorities**:
1. **Critical**: Remediation tracking (RV.3.2), Patch management (RV.3.1), SLA enforcement (RV.3.3)
2. **Medium**: Design review process (PW.1.1), Risk assessment (RV.2.1), Training program (PO.2.1)
3. **Low**: Training metrics (PO.2.2), Certification tracking (PO.2.1)

**Use Cases**:
- Compliance assessment
- Gap remediation planning
- Tool ROI analysis
- Executive reporting

---

### 6. Attestation Generation Flow

**File**: `ATTESTATION_FLOW.md`
**Formats**: Mermaid flowchart, PlantUML activity, ASCII flow
**Complexity**: 7 phases, 40+ steps, 5 artifact types

**Visualizes**:
1. **Data Collection**: Commit data, SBOM, scans, build metadata
2. **SLSA Provenance**: Builder, materials, recipe, metadata
3. **Attestation Statement**: in-toto format with predicate
4. **Cosign Signing**: KMS signing, Fulcio certificates, Rekor log
5. **Storage**: GCS (7-year), OCI registry, PostgreSQL
6. **CISA Form**: Auto-population of all 47 practices
7. **Archival**: Evidence bundle, notifications, dashboard

**Key Features**:
- SLSA provenance v1.0 schema
- in-toto attestation statement
- Cosign signature bundle
- Evidence manifest structure
- PostgreSQL schema
- Verification workflow

**Artifact Examples**:
- SLSA provenance JSON
- in-toto statement JSON
- Cosign signature bundle
- Evidence manifest
- CISA form (PDF + JSON)

**Use Cases**:
- SLSA compliance implementation
- Supply chain security
- CISA attestation submission
- Customer trust and transparency

---

## SSDF Practice Coverage Summary

### Prepare Organization (PO) - 12 Practices - 67% Coverage

| Practice | Status | Evidence | Tools |
|----------|--------|----------|-------|
| PO.1.1 | 🟩 Full | Policy docs, SDLC | git-secrets, pre-commit |
| PO.2.1 | 🟨 Partial | Training records | Security Champions |
| PO.3.1 | 🟩 Full | Evidence manifest | n8n, GCS, PostgreSQL |
| PO.4.1 | 🟩 Full | KPI dashboard | Prometheus, Grafana |
| PO.5.1 | 🟩 Full | SBOM, signatures | Syft, Cosign, SLSA |

**Gaps**: Formal training program (PO.2.1), certification tracking (PO.2.2)

---

### Protect Software (PS) - 7 Practices - 71% Coverage

| Practice | Status | Evidence | Tools |
|----------|--------|----------|-------|
| PS.1.1 | 🟩 Full | Commit logs | Gitea, signed commits |
| PS.2.1 | 🟩 Full | Access audit logs | RBAC, IAM, Vault |
| PS.3.1 | 🟩 Full | Signatures | Cosign, KMS, OCI registry |

**Gaps**: None (2 practices not yet implemented out of 7 total)

---

### Produce Well-Secured Software (PW) - 19 Practices - 63% Coverage

| Practice | Status | Evidence | Tools |
|----------|--------|----------|-------|
| PW.1.1 | 🟨 Partial | Architecture docs | Manual review |
| PW.2.1 | 🟩 Full | SAST reports | SonarQube, Semgrep |
| PW.4.1 | 🟩 Full | SBOM | Syft, CycloneDX |
| PW.7.1 | 🟩 Full | Scan reports | Trivy, Grype, Bandit, Checkov, tfsec, Terrascan, OSV, Docker Bench, SonarQube, Semgrep |
| PW.7.2 | 🟩 Full | DAST reports | OWASP ZAP, Nuclei, SSLyze |
| PW.9.1 | 🟩 Full | Attestations | Cosign, SLSA, in-toto |

**Gaps**: Attack surface analysis (PW.1.3), rollback strategy (PW.8.2)

---

### Respond to Vulnerabilities (RV) - 9 Practices - 33% Coverage

| Practice | Status | Evidence | Tools |
|----------|--------|----------|-------|
| RV.1.1 | 🟩 Full | CVE reports | Trivy, Grype, OSV-Scanner |
| RV.1.2 | 🟩 Full | Runtime alerts | Falco, Wazuh, osquery |
| RV.2.1 | 🟨 Partial | Risk assessments | Dependency Track |
| RV.3.1 | 🟥 Gap | Patch tracking | None - Implement Dependabot/Renovate |
| RV.3.2 | 🟥 Gap | Remediation tracking | None - Implement Jira integration |
| RV.3.3 | 🟥 Gap | SLA enforcement | None - Configure Dependency Track SLAs |

**Gaps**: Patch management (RV.3.1), remediation tracking (RV.3.2), SLA enforcement (RV.3.3)

---

## Tool Integration Summary

### 34 Security Tools Across 9 Categories

| Category | Tools | Integration | Output |
|----------|-------|-------------|--------|
| **SAST** | SonarQube, Semgrep, Bandit, git-secrets | CLI/API | JSON, SARIF |
| **Container** | Trivy, Grype, Syft, Cosign, Docker Bench | CLI | JSON, CycloneDX |
| **IaC** | Checkov, tfsec, Terrascan, Atlantis, Terragrunt | CLI/Webhook | JSON, SARIF |
| **DAST** | OWASP ZAP, Nuclei, SSLyze | API/CLI | XML, JSON |
| **SCA** | OSV-Scanner, Dependency Track, License Finder | CLI/API | JSON |
| **Runtime** | Falco, Wazuh, osquery | gRPC/Agent/CLI | JSON logs |
| **GCP** | SCC, KMS, Logging, Cloud Armor | API | JSON |
| **Monitoring** | Prometheus, Grafana, Loki, Alertmanager | HTTP | Metrics, Logs |
| **Automation** | n8n, HashiCorp Vault | Webhook/API | JSON |

**Total Coverage**: 60% of SSDF practices (28/47)
**Average Tool Utilization**: 6% per tool
**Most Utilized**: Trivy (13%), Cosign (11%), SonarQube (11%)

---

## Evidence Flow Summary

### Collection → Verification → Storage → Dashboard

```
CI/CD Execution → Tool Outputs → n8n Workflow → SHA-256 Hashing →
GCS Upload (7-year) → PostgreSQL Registry → Google Chat Notification →
Dashboard Update → Audit Trail Complete
```

**Evidence Formats**:
- JSON (90% of tools)
- XML (OWASP ZAP)
- SARIF (SonarQube, Checkov)
- CycloneDX (Syft SBOM)
- Signatures (Cosign)

**Storage**:
- **GCS Bucket**: 7-year immutable retention
- **PostgreSQL**: Metadata, indexes, query interface
- **OCI Registry**: Attached attestations

**Security Controls**:
- SHA-256 cryptographic hashing
- Cosign signing with Google Cloud KMS
- Immutable storage with retention policies
- Access control via IAM
- Audit logging for all access

---

## Rendering Instructions

### Batch Rendering All Diagrams

#### Mermaid (Web/PNG)
```bash
#!/bin/bash
# Render all Mermaid diagrams to PNG

for file in *.md; do
  echo "Rendering $file..."
  mmdc -i "$file" \
       -o "${file%.md}.png" \
       -t dark \
       -b transparent \
       -w 2400 \
       -h 2400
done

echo "All diagrams rendered successfully!"
```

#### PlantUML (Submission/PDF)
```bash
#!/bin/bash
# Render all PlantUML diagrams to PNG

docker run --rm -v $(pwd):/data plantuml/plantuml \
  -tpng \
  -DPLANTUML_LIMIT_SIZE=16384 \
  /data/*.md

echo "All PlantUML diagrams rendered!"
```

#### Convert to PDF
```bash
#!/bin/bash
# Convert PNG diagrams to PDF for submission packages

for png in *.png; do
  convert "$png" "${png%.png}.pdf"
done

# Merge all PDFs
pdftk *.pdf cat output SSDF_Architecture_Diagrams_Complete.pdf

echo "PDF package created: SSDF_Architecture_Diagrams_Complete.pdf"
```

---

## Usage Scenarios

### Scenario 1: Customer Presentation

**Goal**: Present SSDF compliance to potential customers

**Diagrams to Use**:
1. `CICD_PIPELINE_ARCHITECTURE.md` - Show complete security pipeline
2. `COMPLIANCE_COVERAGE.md` - Demonstrate 60% coverage with roadmap
3. `ATTESTATION_FLOW.md` - Explain SLSA provenance and transparency

**Format**: Mermaid PNG with dark theme

**Steps**:
```bash
mmdc -i CICD_PIPELINE_ARCHITECTURE.md -o pipeline.png -t dark -b transparent
mmdc -i COMPLIANCE_COVERAGE.md -o coverage.png -t dark -b transparent
mmdc -i ATTESTATION_FLOW.md -o attestation.png -t dark -b transparent

# Add to presentation slides
```

---

### Scenario 2: CISA Attestation Submission

**Goal**: Submit attestation form to CISA for federal compliance

**Diagrams to Use**:
1. All 6 diagrams as supporting evidence
2. `COMPLIANCE_COVERAGE.md` - Gap analysis
3. `ATTESTATION_FLOW.md` - Show CISA form auto-population

**Format**: PDF bundle

**Steps**:
```bash
# Render all as PNG
for file in *.md; do mmdc -i "$file" -o "${file%.md}.png" -t dark -b transparent; done

# Convert to PDF
for png in *.png; do convert "$png" "${png%.png}.pdf"; done

# Merge into submission package
pdftk *.pdf cat output CISA_Supporting_Evidence.pdf

# Include CISA form from attestation workflow
# gs://attestations/YYYY/MM/DD/<commit>/cisa-form.pdf
```

---

### Scenario 3: Security Audit

**Goal**: Third-party security audit for SOC 2 / ISO 27001

**Diagrams to Use**:
1. `CICD_PIPELINE_ARCHITECTURE.md` - Security gates and controls
2. `EVIDENCE_COLLECTION_FLOW.md` - Audit trail and evidence
3. `TOOL_INTEGRATION.md` - Tool coverage and integration

**Format**: PlantUML for detail, ASCII for documentation

**Steps**:
```bash
# Render detailed PlantUML
docker run -v $(pwd):/data plantuml/plantuml -tpng /data/*.md

# Generate audit report
cat << EOF > audit_report.md
# Security Audit - Supporting Evidence

## Architecture Diagrams
[Include all PNG diagrams]

## Evidence Collection
- 7-year retention in GCS
- SHA-256 cryptographic hashing
- PostgreSQL audit trail
- Complete SSDF practice mapping

## Tool Coverage
- 34 security tools integrated
- 60% SSDF compliance (28/47 practices)
- Gap remediation roadmap (12 months)

EOF
```

---

### Scenario 4: Developer Onboarding

**Goal**: Train new developers on secure development pipeline

**Diagrams to Use**:
1. `CICD_PIPELINE_ARCHITECTURE.md` - Understand pipeline stages
2. `SSDF_PRACTICE_FLOW.md` - Learn SSDF practices
3. `TOOL_INTEGRATION.md` - Know which tools to use

**Format**: ASCII in documentation, Mermaid in wiki

**Steps**:
```bash
# Add to wiki/docs
cp *.md /path/to/wiki/architecture/

# Create onboarding guide
cat << EOF > onboarding.md
# Developer Onboarding - Secure Pipeline

## Required Reading
1. CI/CD Pipeline Architecture
2. SSDF Practice Flow (focus on PW practices)
3. Tool Integration (CLI tools you'll use daily)

## Hands-On
1. Run pre-commit hooks locally
2. Create PR with security scans
3. Review SBOM generation
4. Check attestation in dashboard

## Resources
- All diagrams: /ssdf/documentation/diagrams/
- Tool docs: /docs/tools/
- Evidence dashboard: https://dashboard.example.com
EOF
```

---

## Gap Remediation Roadmap

### Phase 1: Critical Gaps (0-3 months) - Target: 75% Coverage

**Priority**: RV practice group (Respond to Vulnerabilities)

| Gap | Practice | Action | Tool | Effort |
|-----|----------|--------|------|--------|
| Patch Management | RV.3.1 | Implement automated patching | Dependabot/Renovate | Medium |
| Remediation Tracking | RV.3.2 | Integrate with Jira | Jira + n8n | Medium |
| SLA Enforcement | RV.3.3 | Configure SLAs in Dependency Track | Dependency Track | Low |

**Expected Outcome**: RV coverage 78% (7/9), overall 70% (33/47)

---

### Phase 2: Medium Gaps (3-6 months) - Target: 85% Coverage

**Priority**: PW design practices

| Gap | Practice | Action | Tool | Effort |
|-----|----------|--------|------|--------|
| Design Review | PW.1.1 | Formalize architecture review | Confluence + checklist | Low |
| Risk Assessment | RV.2.1 | Automate risk scoring | Dependency Track + scripts | Medium |
| Training Program | PO.2.1 | Launch formal security training | LMS platform | High |

**Expected Outcome**: PO 83% (10/12), PW 74% (14/19), overall 85% (40/47)

---

### Phase 3: Optimization (6-12 months) - Target: 95% Coverage

**Priority**: Remaining PO and PW practices

| Gap | Practice | Action | Tool | Effort |
|-----|----------|--------|------|--------|
| Attack Surface Analysis | PW.1.3 | Implement tool or manual process | AttackSurfaceAnalyzer | High |
| Training Metrics | PO.2.2 | Track completion and attestations | LMS + n8n | Low |
| Rollback Strategy | PW.8.2 | Document and test rollback | Atlantis + runbooks | Medium |

**Expected Outcome**: Overall 95% (45/47), CISA attestation ready

---

## References and Standards

### NIST Publications
- **NIST SP 800-218**: Secure Software Development Framework Version 1.1
- **NIST SP 800-53 Rev. 5**: Security and Privacy Controls for Information Systems
- **NIST SP 800-171 Rev. 2**: Protecting Controlled Unclassified Information

### Supply Chain Security
- **SLSA**: Supply-chain Levels for Software Artifacts (slsa.dev)
- **in-toto**: Supply chain security attestation framework (in-toto.io)
- **Sigstore**: Cosign, Fulcio, Rekor (sigstore.dev)

### SBOM Standards
- **CycloneDX**: OWASP SBOM specification (cyclonedx.org)
- **SPDX**: Software Package Data Exchange (spdx.dev)

### Federal Compliance
- **CISA**: Secure Software Development Attestation Form
- **EO 14028**: Executive Order on Improving the Nation's Cybersecurity
- **OMB M-22-18**: Enhancing the Security of the Software Supply Chain

### Tool Documentation
- **Trivy**: aquasecurity.github.io/trivy
- **Cosign**: docs.sigstore.dev/cosign
- **SonarQube**: docs.sonarqube.org
- **OWASP ZAP**: www.zaproxy.org/docs
- **Dependency Track**: docs.dependencytrack.org

---

## Maintenance and Updates

### Diagram Update Schedule

| Diagram | Update Frequency | Trigger | Owner |
|---------|------------------|---------|-------|
| CI/CD Pipeline | Monthly | Tool additions, stage changes | DevSecOps Team |
| SSDF Practice Flow | Quarterly | Practice implementation | Security Team |
| Evidence Collection | As needed | Workflow changes | Automation Team |
| Tool Integration | Monthly | Tool additions/removals | DevSecOps Team |
| Compliance Coverage | Weekly | Practice implementation | Compliance Team |
| Attestation Flow | As needed | SLSA/Cosign updates | Security Team |

### Version Control

All diagrams are version controlled in the Git repository:
- **Branch**: `feature/ssdf-cicd-pipeline`
- **Path**: `/ssdf/documentation/diagrams/`
- **Commit Strategy**: Atomic commits per diagram with descriptive messages

### Change Log

| Date | Diagram | Change | Reason |
|------|---------|--------|--------|
| 2025-10-07 | All | Initial creation | SSDF implementation documentation |
| TBD | Compliance Coverage | Update with Phase 1 gap closure | Quarterly review |
| TBD | Tool Integration | Add new runtime security tool | Tool evaluation |

---

## Support and Contact

### Questions or Issues?

- **DevSecOps Team**: devsecops@example.com
- **Security Team**: security@example.com
- **Compliance Team**: compliance@example.com

### Contributing

To update or add diagrams:

1. Create feature branch: `git checkout -b feature/update-diagrams`
2. Update diagram file(s) in `/ssdf/documentation/diagrams/`
3. Render and verify: `mmdc -i DIAGRAM.md -o DIAGRAM.png`
4. Commit with descriptive message: `git commit -m "Update: Add XYZ tool to integration diagram"`
5. Create pull request with review request

---

## Appendix: File Checksums

Verify diagram integrity:

```bash
cd /home/notme/Desktop/gitea/ssdf/documentation/diagrams/

sha256sum *.md
```

Expected output:
```
[To be generated after final commit]
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-07
**SSDF Compliance**: 60% (28/47 practices implemented)
**Target Compliance**: 95% (45/47 practices) by 2026-10-07
**CISA Attestation**: Ready for submission with gap remediation plan
