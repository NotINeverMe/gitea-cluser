# SSDF Evidence Collection Framework

Comprehensive evidence collection system for NIST SSDF (Secure Software Development Framework) compliance in CI/CD pipelines.

## Overview

This framework automates the collection, validation, storage, and querying of SSDF compliance evidence from DevSecOps pipelines. Evidence is collected from multiple security tools, packaged with cryptographic verification, and stored in GCS with 7-year retention.

## Architecture

```
CI/CD Pipeline → Evidence Collector → Packaging → GCS Storage
                      ↓                              ↓
                 PostgreSQL Registry ← Query Tool ← Verification
```

## Components

### 1. Evidence Collector (`ssdf-evidence-collector.py`)

Main collection engine that gathers evidence from:

- **Gitea Actions**: Workflow outputs and artifacts
- **SonarQube**: SAST scan results and code quality metrics
- **Trivy**: Container, filesystem, and IaC vulnerability scans
- **Syft**: SBOM generation (SPDX and CycloneDX formats)
- **Cosign**: Build attestations and cryptographic signatures
- **n8n**: Workflow execution logs

**Usage:**

```bash
python ssdf-evidence-collector.py \
  --repository owner/repo-name \
  --workflow-id 12345 \
  --run-number 42 \
  --commit-sha abc123def456 \
  --sonar-project my-project-key
```

**Environment Variables:**

```bash
export GITEA_TOKEN="your-gitea-token"
export SONARQUBE_TOKEN="your-sonarqube-token"
export GCP_PROJECT="your-gcp-project"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
export POSTGRES_PASSWORD="your-db-password"
```

### 2. Manifest Generator (`manifest-generator.py`)

Generates detailed evidence manifests with SHA-256 hashes and SSDF practice mappings.

**Features:**

- SHA-256 hash calculation for all evidence files
- SSDF practice to evidence mapping
- Compliance coverage statistics
- Tool inventory and usage tracking
- Retention policy metadata

**Usage:**

```bash
# Verify manifest integrity
python manifest-generator.py verify <build-id>

# Generate summary report
python manifest-generator.py summary <build-id>

# List all manifests
python manifest-generator.py list
```

**Manifest Structure:**

```json
{
  "manifest_version": "1.0",
  "build_id": "uuid",
  "repository": "owner/repo",
  "commit_sha": "abc123",
  "timestamp": "2025-10-07T00:00:00Z",
  "ssdf_practices_covered": [
    {
      "practice": "PW.6.1",
      "title": "Use automated SAST tools",
      "tool": "SonarQube",
      "evidence": "sonar-report.json",
      "verification_method": "SonarQube quality gate analysis"
    }
  ],
  "evidence_files": [
    {
      "filename": "sonar-report.json",
      "hash": "sha256:abc...",
      "size": 12345,
      "tool": "SonarQube",
      "format": "JSON"
    }
  ],
  "compliance_summary": {
    "total_practices": 42,
    "practices_covered": 38,
    "coverage_percent": 90.5
  }
}
```

### 3. Evidence Verifier (`verify-evidence.py`)

Downloads and verifies evidence packages from GCS.

**Verification Checks:**

1. ✓ GCS Download
2. ✓ Package Extraction
3. ✓ Manifest Discovery
4. ✓ Manifest Integrity
5. ✓ File Hash Verification
6. ✓ SSDF Coverage
7. ✓ Signature Verification

**Usage:**

```bash
# Verify from GCS
python verify-evidence.py \
  --gcs-uri gs://compliance-evidence-ssdf/repo/2025/10/build-id/evidence.tar.gz \
  --report verification-report.txt \
  --json result.json

# Verify local package
python verify-evidence.py \
  --local /path/to/evidence.tar.gz \
  --report report.txt
```

**Exit Codes:**

- `0`: Verification passed
- `1`: Verification failed

### 4. Evidence Query Tool (`query-evidence.py`)

Query and search evidence from PostgreSQL database and GCS storage.

**Query Operations:**

```bash
# Query by date range
python query-evidence.py --start 2025-01-01 --end 2025-12-31

# Query by repository
python query-evidence.py --repo my-app

# Query by SSDF practice
python query-evidence.py --practice PW.9.1

# Query by tool
python query-evidence.py --tool Trivy

# Query by commit
python query-evidence.py --commit abc123def456

# Generate compliance report (text)
python query-evidence.py --report --repo my-app

# Generate compliance report (markdown)
python query-evidence.py --report --format markdown --output report.md

# Generate compliance report (JSON)
python query-evidence.py --report --format json --output report.json

# Export to CSV
python query-evidence.py --repo my-app --csv evidence.csv

# List GCS evidence
python query-evidence.py --list-gcs --repo my-app

# Show coverage statistics
python query-evidence.py --repo my-app
```

## Storage Structure

### GCS Bucket Organization

```
gs://compliance-evidence-ssdf/
├── repo-name/
│   ├── 2025/
│   │   ├── 01/
│   │   │   ├── build-uuid-1/
│   │   │   │   └── evidence-build-uuid-1.tar.gz
│   │   │   └── build-uuid-2/
│   │   │       └── evidence-build-uuid-2.tar.gz
│   │   └── 10/
│   │       └── build-uuid-3/
│   │           └── evidence-build-uuid-3.tar.gz
│   └── another-repo/
└── logs/
```

### Evidence Package Contents

```
evidence-{build-id}.tar.gz
├── manifest.json
├── workflow-metadata.json
├── sonarqube-measures.json
├── sonarqube-issues.json
├── trivy-container-scan.json
├── trivy-fs-scan.json
├── sbom.spdx.json
├── sbom.cyclonedx.json
├── provenance.json
├── provenance.json.sig
└── attestation.json
```

## Database Schema

### Tables

#### `evidence_registry`

Primary table for evidence tracking.

```sql
CREATE TABLE evidence_registry (
    id UUID PRIMARY KEY,
    repository VARCHAR(255),
    commit_sha VARCHAR(40),
    workflow_id BIGINT,
    practices_covered TEXT[],
    evidence_path VARCHAR(512),
    evidence_hash VARCHAR(64),
    collected_at TIMESTAMP,
    tools_used JSONB
);
```

#### `practice_coverage`

Detailed SSDF practice coverage tracking.

```sql
CREATE TABLE practice_coverage (
    id UUID PRIMARY KEY,
    evidence_id UUID REFERENCES evidence_registry(id),
    practice_id VARCHAR(10),
    practice_group VARCHAR(5),
    tool_name VARCHAR(100),
    evidence_file VARCHAR(255),
    verification_method TEXT,
    verified BOOLEAN
);
```

#### `tools_inventory`

Tool usage tracking.

```sql
CREATE TABLE tools_inventory (
    id UUID PRIMARY KEY,
    tool_name VARCHAR(100) UNIQUE,
    tool_type VARCHAR(50),
    usage_count INTEGER,
    practices_supported TEXT[]
);
```

### Views

- `compliance_summary`: Repository-level compliance statistics
- `practice_frequency`: Practice usage across all builds
- `tool_usage`: Tool usage statistics

### Setup

```bash
# Initialize database
psql -U postgres -f schemas/evidence-registry.sql

# Verify tables
psql -U postgres -d compliance -c "\dt"
```

## Retention Policy

### GCS Lifecycle Rules

**Policy File:** `retention-policy.json`

| Age | Action | Storage Class |
|-----|--------|---------------|
| 0-90 days | None | STANDARD |
| 90-365 days | Transition | COLDLINE |
| 365-2555 days | Transition | ARCHIVE |
| 2555+ days | Delete | N/A |

**Total Retention:** 7 years (2,555 days)

### Apply Retention Policy

```bash
# Set lifecycle policy
gsutil lifecycle set retention-policy.json gs://compliance-evidence-ssdf

# Verify policy
gsutil lifecycle get gs://compliance-evidence-ssdf

# Enable versioning
gsutil versioning set on gs://compliance-evidence-ssdf

# Enable logging
gsutil logging set on -b gs://compliance-evidence-ssdf-logs \
  gs://compliance-evidence-ssdf
```

## SSDF Practice Mapping

### Practice Groups

- **PO** (Prepare the Organization): 7 practices
- **PS** (Protect the Software): 3 practices
- **PW** (Produce Well-Secured Software): 14 practices
- **RV** (Respond to Vulnerabilities): 6 practices

**Total:** 30+ practices

### Tool to Practice Mapping

| Tool | Practices | Evidence Type |
|------|-----------|---------------|
| Gitea Actions | PO.3.1, PO.3.2 | Workflow metadata, artifacts |
| SonarQube | PW.6.1, PW.7.1 | SAST results, code quality |
| Trivy | PW.8.1, PW.8.2 | Vulnerability scans |
| Syft | PW.9.1, PW.9.2 | SBOM (SPDX, CycloneDX) |
| Cosign | PS.2.1 | Signatures, attestations |
| Grype | PW.8.1 | Vulnerability scans |

### Required Practices (Minimum Coverage)

Critical practices that must be covered:

- `PO.3.1`: Automated build processes
- `PW.6.1`: Automated SAST tools
- `PW.8.1`: Vulnerability scanning
- `PW.9.1`: SBOM generation
- `PS.2.1`: Cryptographic signing

## CI/CD Integration

### Gitea Actions Workflow

```yaml
name: SSDF Evidence Collection

on:
  push:
    branches: [main]
  pull_request:

jobs:
  collect-evidence:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run security scans
        run: |
          # SonarQube scan
          sonar-scanner

          # Trivy scans
          trivy image --format json --output trivy-container.json myapp:latest
          trivy fs --format json --output trivy-fs.json .

          # Generate SBOM
          syft myapp:latest -o spdx-json > sbom.spdx.json
          syft myapp:latest -o cyclonedx-json > sbom.cyclonedx.json

          # Sign artifacts
          cosign sign --key cosign.key myapp:latest
          cosign attest --key cosign.key --predicate provenance.json myapp:latest

      - name: Collect evidence
        env:
          GITEA_TOKEN: ${{ secrets.GITEA_TOKEN }}
          SONARQUBE_TOKEN: ${{ secrets.SONARQUBE_TOKEN }}
          GCP_PROJECT: ${{ secrets.GCP_PROJECT }}
          GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_CREDENTIALS }}
        run: |
          python /path/to/ssdf-evidence-collector.py \
            --repository ${{ github.repository }} \
            --workflow-id ${{ github.run_id }} \
            --run-number ${{ github.run_number }} \
            --commit-sha ${{ github.sha }} \
            --sonar-project ${{ secrets.SONAR_PROJECT_KEY }}

      - name: Upload evidence package
        uses: actions/upload-artifact@v4
        with:
          name: evidence-package
          path: evidence-*.tar.gz
          retention-days: 90
```

### n8n Workflow Integration

Create n8n workflow to trigger evidence collection on build completion:

1. **Webhook Trigger**: Listen for CI/CD completion
2. **Extract Build Info**: Parse webhook payload
3. **Run Collector**: Execute evidence collector script
4. **Verify Evidence**: Run verification checks
5. **Notify**: Send notifications on completion/failure

## Configuration

### Collector Configuration

**File:** `config/collector-config.json`

Key settings:

- `gitea.url`: Gitea instance URL
- `sonarqube.url`: SonarQube instance URL
- `gcs.bucket`: GCS bucket name
- `database.host`: PostgreSQL host
- `evidence.retention_days`: Retention period (default: 2555)
- `verification.minimum_coverage`: Minimum SSDF coverage % (default: 80)

### Environment Variables

Create `.env` file:

```bash
# Gitea
GITEA_URL=http://localhost:3000
GITEA_TOKEN=your-gitea-token

# SonarQube
SONARQUBE_URL=http://localhost:9000
SONARQUBE_TOKEN=your-sonarqube-token

# GCS
GCP_PROJECT=your-gcp-project
GCS_EVIDENCE_BUCKET=compliance-evidence-ssdf
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json

# PostgreSQL
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=compliance
POSTGRES_USER=evidence_collector
POSTGRES_PASSWORD=your-secure-password

# Cosign
COSIGN_KEY_PATH=/path/to/cosign.key
```

## Installation

### Prerequisites

- Python 3.11+
- PostgreSQL 14+
- Google Cloud SDK
- Cosign (optional, for signature verification)

### Install Dependencies

```bash
pip install -r requirements.txt
```

**requirements.txt:**

```txt
google-cloud-storage>=2.10.0
psycopg2-binary>=2.9.9
requests>=2.31.0
python-dateutil>=2.8.2
pyyaml>=6.0.1
```

### Setup

```bash
# 1. Create GCS bucket
gsutil mb -c STANDARD -l us-central1 gs://compliance-evidence-ssdf
gsutil lifecycle set retention-policy.json gs://compliance-evidence-ssdf

# 2. Initialize database
psql -U postgres -f schemas/evidence-registry.sql

# 3. Configure environment
cp .env.example .env
# Edit .env with your settings

# 4. Test collector
python ssdf-evidence-collector.py --help

# 5. Test query tool
python query-evidence.py --help
```

## Security Considerations

### Access Control

1. **GCS Bucket**: Use IAM with principle of least privilege
2. **PostgreSQL**: Separate roles for collection vs. query
3. **API Tokens**: Store in secrets manager (not in code)
4. **Evidence Packages**: Signed with Cosign for tamper detection

### Encryption

- **At Rest**: GCS encryption with KMS keys
- **In Transit**: TLS for all API communications
- **Signatures**: ECDSA-P256-SHA256 for attestations

### Audit Trail

- All evidence collection logged to PostgreSQL
- GCS access logs enabled
- Database audit triggers on modifications

## Troubleshooting

### Common Issues

**Issue:** `Failed to download from GCS`

```bash
# Verify credentials
gcloud auth application-default login

# Check bucket access
gsutil ls gs://compliance-evidence-ssdf
```

**Issue:** `Database connection failed`

```bash
# Test connection
psql -h localhost -U evidence_collector -d compliance -c "SELECT 1;"

# Check pg_hba.conf for access rules
```

**Issue:** `Low SSDF coverage`

```bash
# Check which practices are missing
python query-evidence.py --repo my-app

# Verify tool integrations are enabled in config
cat config/collector-config.json | jq '.tools'
```

## Reporting

### Generate Compliance Report

```bash
# Full compliance report
python query-evidence.py \
  --report \
  --repo my-app \
  --format markdown \
  --output compliance-report.md

# Practice frequency analysis
psql -U evidence_query -d compliance \
  -c "SELECT * FROM practice_frequency LIMIT 20;"

# Coverage trends
psql -U evidence_query -d compliance \
  -c "SELECT * FROM compliance_summary;"
```

## API Reference

See individual script documentation:

```bash
python ssdf-evidence-collector.py --help
python manifest-generator.py --help
python verify-evidence.py --help
python query-evidence.py --help
```

## License

Internal Use Only - Compliance Framework

## Support

For issues or questions:
- Check logs: `/var/log/evidence-collector.log`
- Review configuration: `config/collector-config.json`
- Query database: `psql -U evidence_query -d compliance`

## Version

**Framework Version:** 1.0.0
**SSDF Version:** NIST SSDF 1.1
**Last Updated:** 2025-10-07
