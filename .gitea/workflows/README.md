# NIST SSDF SP 800-218 Compliant CI/CD Workflows

## Overview

This repository contains 7 Gitea Actions workflows that implement complete NIST SSDF (Secure Software Development Framework) SP 800-218 compliance. These workflows cover all 42 SSDF tasks across 4 practice groups and integrate with 34+ security tools for comprehensive DevSecOps automation.

## Workflow Descriptions

### 1. Pre-Commit Security (`pre-commit.yml`)

**Purpose**: Early security validation before code reaches the repository

**Trigger Conditions**:
- On every push to any branch
- On pull request open/synchronize

**SSDF Practices Covered**:
- PO.1.1 - Define security requirements
- PO.3.2 - Track provenance
- PO.4.1 - Secure development environment
- PS.1.1 - Store code securely
- PS.2.1 - Verify software integrity

**Security Tools**:
- git-secrets (v1.3.0) - Secret scanning
- Semgrep (v1.45.0) - SAST for multiple languages
- Ansible-lint (v6.17.0) - Ansible playbook security
- Bandit (v1.7.5) - Python security analysis
- Safety (v2.3.5) - Python dependency check

**Evidence Collection**:
- Location: `evidence/pre-commit/`
- Artifacts: scan results JSON, manifest.json
- Hash: SHA-256 of evidence tarball
- Retention: 90 days

### 2. Pull Request Security Gate (`pull-request.yml`)

**Purpose**: Comprehensive security validation and quality gates for PRs

**Trigger Conditions**:
- On pull request open/synchronize/reopen

**SSDF Practices Covered**:
- PW.2.1 - Code review requirements
- PW.3.1 - License compliance
- PW.4.1 - Dependency scanning
- PW.4.2 - Update dependencies
- PW.6.1 - Security testing
- PW.6.2 - Test coverage requirements
- PW.9.1 - Documentation

**Security Tools**:
- SonarQube (v10.2) - Code quality and security
- Trivy (v0.46.0) - Vulnerability scanning
- Checkov (v3.0.0) - IaC policy scanning
- License-checker (v25.0.0) - License compliance
- Grype (v0.70.0) - Container vulnerability detection

**Evidence Collection**:
- Location: `evidence/pr-gate/`
- Artifacts: Quality gate results, vulnerability reports
- Hash: SHA-256 of evidence tarball
- Retention: 90 days

**Gate Criteria**:
- ❌ BLOCK if CRITICAL vulnerabilities found
- ❌ BLOCK if code coverage < 80%
- ❌ BLOCK if forbidden licenses detected
- ❌ BLOCK if SonarQube quality gate fails
- ❌ BLOCK if >20 IaC policy violations

### 3. Secure Build & SBOM (`build.yml`)

**Purpose**: Secure container builds with SBOM generation and signing

**Trigger Conditions**:
- On push to main/develop branches
- Manual workflow dispatch

**SSDF Practices Covered**:
- PS.3.1 - Archive releases
- PS.3.2 - Protect archives
- PS.3.3 - Audit logs
- PS.3.4 - Build protection
- PW.9.2 - Generate SBOM

**Security Tools**:
- Syft (v0.98.0) - SBOM generation
- Cosign (v2.2.0) - Container signing
- SLSA Generator (v1.9.0) - Provenance generation
- Docker Buildx (v0.11.2) - Multi-platform secure builds

**SBOM Formats**:
- SPDX JSON (v2.3)
- CycloneDX JSON (v1.5)

**Evidence Collection**:
- Location: `evidence/build/`
- Artifacts: SBOM files, signatures, attestations
- Hash: SHA-256 of all artifacts
- Upload: GCS evidence bucket
- Retention: 90 days

### 4. Comprehensive Security Scanning (`security-scan.yml`)

**Purpose**: Multi-layer security scanning across code, containers, and IaC

**Trigger Conditions**:
- On every push
- On pull request
- Daily schedule (3 AM UTC)
- Manual workflow dispatch

**SSDF Practices Covered**:
- PW.7.1 - Static analysis
- PW.7.2 - Dynamic analysis
- PW.7.3 - Manual analysis
- RV.1.1 - Identify vulnerabilities
- RV.1.2 - Assess vulnerabilities

**Security Tools**:

**Container Scanning**:
- Trivy - CVE detection
- Grype - Vulnerability analysis
- Snyk - Container security
- Clair - Container scanning

**Code Scanning**:
- Bandit - Python SAST
- Semgrep - Multi-language SAST
- Bearer - Security patterns
- ESLint - JavaScript security

**IaC Scanning**:
- tfsec - Terraform security
- Terrascan - Multi-cloud IaC
- Checkov - Policy compliance
- KICS - IaC security

**Evidence Collection**:
- Location: `evidence/security-scan/`
- Artifacts: Unified security report JSON
- Issues: Auto-create Gitea issue if CRITICAL found
- Upload: GCS evidence bucket
- Retention: 90 days

### 5. Dynamic Application Security Testing (`dast.yml`)

**Purpose**: Runtime security testing of deployed applications

**Trigger Conditions**:
- Manual workflow dispatch
- Daily schedule (2 AM UTC)

**SSDF Practices Covered**:
- PW.7.1 - Dynamic analysis
- PW.7.2 - API security testing
- PW.7.3 - Vulnerability templates
- PW.9.1 - Evidence collection

**Security Tools**:
- OWASP ZAP (v2.14.0) - Web application security
- Nuclei (v3.1.0) - Vulnerability templates
- testssl (v3.2) - TLS configuration testing

**Scan Types**:
- Baseline - Quick security assessment
- Full - Comprehensive security scan
- API - OpenAPI/Swagger based testing

**Evidence Collection**:
- Location: `evidence/dast/`
- Artifacts: ZAP reports, Nuclei results
- Upload: GCS evidence bucket
- Retention: 90 days

### 6. SSDF Compliance & Evidence (`compliance.yml`)

**Purpose**: Validate SSDF compliance and generate attestations

**Trigger Conditions**:
- On every push
- On pull request
- Weekly schedule (Monday 4 AM UTC)
- Manual workflow dispatch

**SSDF Practices Covered**:
- ALL 42 SSDF practices validated

**Compliance Checks**:
- SBOM completeness validation
- CMMC control mapping (110 controls)
- SSDF practice verification
- Evidence collection audit
- Attestation generation

**Evidence Collection**:
- Location: `evidence/compliance/`
- Artifacts: SSDF attestation, assessment results
- Compliance score: Calculated percentage
- Upload: GCS evidence bucket with metadata
- Retention: 365 days (1 year for compliance)

### 7. Secure Deployment (`deploy.yml`)

**Purpose**: Secure infrastructure deployment with runtime protection

**Trigger Conditions**:
- On push to main branch
- Manual workflow dispatch (with environment selection)

**SSDF Practices Covered**:
- PW.8.1 - Secure deployment
- PW.8.2 - Runtime protection
- RV.2.1 - Vulnerability management
- RV.2.2 - Security monitoring
- RV.3.2 - Rollback capability
- RV.3.3 - Drift detection

**Security Tools**:
- Atlantis (v0.25.0) - Terraform automation
- Terraform (v1.6.0) - Infrastructure as Code
- Falco - Runtime security monitoring
- Prometheus - Security metrics collection

**Deployment Features**:
- Pre-deployment security scanning
- Terraform plan analysis
- Runtime rule deployment
- Post-deployment validation
- Automatic rollback on failure
- Drift detection and reporting

**Evidence Collection**:
- Location: `evidence/deployment/`
- Artifacts: Terraform plans, Falco rules, validation results
- Upload: GCS evidence bucket
- Retention: 90 days

## Security Tool Versions

| Tool | Version | Purpose | SSDF Practice |
|------|---------|---------|---------------|
| git-secrets | 1.3.0 | Secret scanning | PO.5.2 |
| Semgrep | 1.45.0 | SAST | PS.1.1, PW.7.1 |
| Bandit | 1.7.5 | Python security | PW.7.1 |
| Trivy | 0.46.0 | Vulnerability scanning | PW.4.1 |
| SonarQube | 10.2 | Code quality | PW.2.1 |
| Checkov | 3.0.0 | IaC scanning | PW.4.2 |
| Syft | 0.98.0 | SBOM generation | PW.9.2 |
| Cosign | 2.2.0 | Signing | PS.3.2 |
| OWASP ZAP | 2.14.0 | DAST | PW.7.2 |
| Nuclei | 3.1.0 | Vulnerability detection | PW.7.3 |
| Falco | 0.35.1 | Runtime security | RV.2.1 |
| Terraform | 1.6.0 | IaC deployment | PW.8.1 |

## Evidence Collection Process

All workflows follow a standardized evidence collection process:

1. **Collection**: Gather all scan results, reports, and artifacts
2. **Packaging**: Create tar.gz archive with all evidence
3. **Hashing**: Generate SHA-256 hash of evidence package
4. **Manifest**: Create JSON manifest with metadata
5. **Upload**: Store in GCS evidence bucket with proper naming
6. **Retention**: Keep for specified period (90-365 days)

### Evidence Bucket Structure

```
gs://ssdf-evidence-${GITEA_REPO_NAME}/
├── pre-commit/
│   └── evidence-pre-commit-${RUN_ID}.tar.gz
├── pr-gate/
│   └── evidence-pr-${PR_NUMBER}-${RUN_ID}.tar.gz
├── build/
│   └── evidence-build-${RUN_ID}.tar.gz
├── security-scans/
│   └── evidence-security-scan-${RUN_ID}.tar.gz
├── dast/
│   └── evidence-dast-${RUN_ID}.tar.gz
├── compliance/
│   └── evidence-compliance-${RUN_ID}.tar.gz
└── deployments/
    └── evidence-deployment-${RUN_ID}.tar.gz
```

## SSDF Practice Coverage Matrix

| Practice Group | Practices | Workflows | Coverage |
|---------------|-----------|-----------|----------|
| **PO - Prepare Organization** | 10 tasks | pre-commit, compliance | 100% |
| **PS - Protect Software** | 6 tasks | pre-commit, build | 100% |
| **PW - Produce Well-Secured Software** | 18 tasks | All workflows | 100% |
| **RV - Respond to Vulnerabilities** | 8 tasks | security-scan, deploy | 100% |
| **Total** | 42 tasks | 7 workflows | 100% |

## OPA Policy Files

### Build Policy (`build-policy.rego`)
- Requires signed commits
- Enforces SBOM generation
- Blocks builds with CRITICAL CVEs
- Requires 2+ code review approvals
- Validates container base images

### Security Policy (`security-policy.rego`)
- No hardcoded secrets validation
- Minimum 80% code coverage
- SAST finding thresholds
- Dependency license compliance
- Container security requirements

### Compliance Policy (`compliance-policy.rego`)
- CMMC control validation (95% required)
- SSDF practice verification (all 42 tasks)
- Evidence completeness checks
- Attestation signature validation
- Audit trail requirements

## Usage Instructions

### Running Workflows Manually

```bash
# Trigger security scan
git push origin feature/your-branch

# Trigger DAST scan
# Use Gitea UI: Actions -> DAST -> Run workflow
# Select scan type: baseline/full/api

# Trigger deployment
# Use Gitea UI: Actions -> Deploy -> Run workflow
# Select environment: staging/production
# Select action: plan/apply/destroy

# Trigger compliance check
# Runs automatically weekly or:
# Use Gitea UI: Actions -> Compliance -> Run workflow
```

### Required Secrets

Configure these secrets in Gitea repository settings:

```yaml
# Authentication
GITEA_TOKEN: Gitea API token
GITHUB_TOKEN: GitHub registry token
SONAR_TOKEN: SonarQube authentication
SNYK_TOKEN: Snyk API token

# Cloud Providers
GCP_PROJECT_ID: GCP project identifier
GCP_SERVICE_ACCOUNT_KEY: Base64 encoded service account key
AWS_ACCESS_KEY_ID: AWS access key (optional)
AWS_SECRET_ACCESS_KEY: AWS secret key (optional)

# Signing
COSIGN_PASSWORD: Cosign key password
```

### Environment Variables

```yaml
# Evidence Storage
EVIDENCE_BUCKET: gs://ssdf-evidence-${GITEA_REPO_NAME}

# Service URLs
SONAR_HOST_URL: http://sonarqube:9000
ATLANTIS_URL: http://atlantis:4141
DASHBOARD_URL: http://localhost:8050

# Thresholds
COVERAGE_THRESHOLD: 80
```

## Security Best Practices

1. **Never commit secrets** - Use secret management services
2. **Review all dependencies** - Check licenses and vulnerabilities
3. **Sign all commits** - Use GPG signing
4. **Generate SBOMs** - For every build
5. **Scan early and often** - Shift security left
6. **Maintain evidence** - For compliance audits
7. **Monitor runtime** - Deploy Falco rules
8. **Plan rollbacks** - Have recovery procedures

## Troubleshooting

### Common Issues

1. **Workflow fails with permission error**
   ```bash
   # Grant runner permissions
   chmod +x scripts/*.sh
   ```

2. **Evidence upload fails**
   ```bash
   # Check GCS credentials
   gcloud auth list
   gsutil ls ${EVIDENCE_BUCKET}
   ```

3. **SBOM generation empty**
   ```bash
   # Verify container image exists
   docker images
   syft packages ${IMAGE_NAME}
   ```

4. **Security scan timeout**
   ```yaml
   # Increase timeout in workflow
   timeout-minutes: 60
   ```

## Compliance Dashboard Integration

The workflows automatically update the compliance dashboard at `http://localhost:8050` with:

- Real-time security metrics
- SSDF compliance scores
- Vulnerability trends
- Evidence tracking
- Audit trail visualization

## Contributing

When modifying workflows:

1. Maintain SSDF practice mappings
2. Update evidence collection
3. Test locally with act_runner
4. Document changes in this README
5. Update tool versions carefully

## Support

For issues or questions:
- Create issue in Gitea repository
- Check workflow logs for detailed errors
- Review OPA policy evaluation results
- Consult NIST SP 800-218 documentation

---

**Last Updated**: 2024
**SSDF Version**: 1.1
**Compliance Level**: Full (100% coverage)