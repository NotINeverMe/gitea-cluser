# SSDF Compliance n8n Workflows

This directory contains n8n workflow automations for SSDF (Secure Software Development Framework) compliance evidence collection and vulnerability management.

## Workflows Overview

### 1. SSDF Evidence Collection (`ssdf-evidence-collection.json`)
Automatically collects and packages SSDF compliance evidence from multiple security tools when Gitea Actions workflows complete.

**Key Features:**
- Collects reports from SonarQube, Trivy, Syft, Cosign, and Checkov
- Creates tamper-evident packages with SHA-256 hashes
- Generates SSDF practice coverage manifest
- Archives evidence in GCS with metadata
- Sends confirmation via Google Chat

**SSDF Practices Covered:**
- PS.1.1, PS.2.1, PS.3.1 (Protect Software)
- PW.1.1, PW.4.1, PW.5.1, PW.6.1, PW.7.1, PW.8.1 (Produce Well-Secured Software)
- RV.1.1, RV.1.2 (Respond to Vulnerabilities)

### 2. SBOM Management (`sbom-management.json`)
Manages Software Bill of Materials (SBOM) lifecycle including vulnerability checking and license compliance.

**Key Features:**
- Parses SPDX/CycloneDX/Syft formats
- Checks vulnerabilities against OSV, GitHub Advisory, and NVD
- Validates license compliance (allowlist/blocklist)
- Tracks outdated dependencies (>90 days)
- Creates Gitea issues for critical findings
- Updates dashboard metrics

### 3. Vulnerability Response Automation (`vulnerability-response.json`)
Automates vulnerability response workflow based on severity with SLA tracking.

**Key Features:**
- Severity-based routing:
  - CRITICAL: PagerDuty + Google Chat + Issue (24h SLA)
  - HIGH: Google Chat + Issue (72h SLA)
  - MEDIUM: Issue only (7d SLA)
  - LOW: Weekly digest (30d SLA)
- Deduplication to prevent duplicate issues
- SLA tracking with reminders
- Evidence collection for compliance

### 4. Attestation Generation (`attestation-generation.json`)
Generates signed SSDF attestations and SLSA provenance for successful builds.

**Key Features:**
- Creates SLSA v1.0 provenance
- Generates SSDF compliance attestation
- Signs with Cosign
- Creates CISA attestation form (PDF)
- 7-year retention in archive storage
- Complete audit trail

## Deployment Instructions

### Prerequisites

1. **n8n Instance**
   - Version: 1.0.0 or higher
   - Required nodes: webhook, httpRequest, postgres, googleCloudStorage, googleChat, code

2. **PostgreSQL Database**
   - Create database: `compliance_db`
   - Run schema migrations (see `schema.sql`)

3. **Google Cloud Storage**
   - Create bucket: `compliance-evidence-ssdf`
   - Enable versioning and audit logging
   - Set up lifecycle rules for archive storage

4. **API Credentials**
   - Gitea API key
   - Google Cloud service account
   - Google Chat OAuth2 credentials
   - PagerDuty API key (optional)
   - Cosign signing key

### Installation Steps

1. **Import Workflows into n8n**
   ```bash
   # Via n8n CLI
   n8n import:workflow --input=ssdf-evidence-collection.json
   n8n import:workflow --input=sbom-management.json
   n8n import:workflow --input=vulnerability-response.json
   n8n import:workflow --input=attestation-generation.json
   ```

   Or import via n8n UI:
   - Navigate to Workflows
   - Click "Import from File"
   - Select each JSON file

2. **Configure Credentials**

   In n8n UI, create the following credentials:

   a. **Gitea API Key** (ID: `gitea-api-key`)
   ```json
   {
     "headerName": "Authorization",
     "headerValue": "token YOUR_GITEA_TOKEN"
   }
   ```

   b. **GCS OAuth2** (ID: `gcs-oauth`)
   - Use service account JSON
   - Scopes: `https://www.googleapis.com/auth/devstorage.read_write`

   c. **Google Chat OAuth2** (ID: `gchat-oauth`)
   - Configure OAuth2 app in Google Cloud Console
   - Scopes: `https://www.googleapis.com/auth/chat.bot`

   d. **PostgreSQL** (ID: `postgres-creds`)
   ```json
   {
     "host": "postgres-host",
     "port": 5432,
     "database": "compliance_db",
     "user": "n8n_user",
     "password": "secure_password"
   }
   ```

   e. **PagerDuty API** (ID: `pagerduty-api`, optional)
   ```json
   {
     "apiKey": "YOUR_PAGERDUTY_KEY"
   }
   ```

3. **Configure Webhooks in Gitea**

   Add webhooks to your Gitea repositories:

   a. **Workflow Completion**
   - URL: `http://n8n-host:5678/webhook/gitea-workflow-complete`
   - Events: Workflow runs
   - Content-Type: `application/json`

   b. **Build Success**
   - URL: `http://n8n-host:5678/webhook/build-success-trigger`
   - Events: Push, Pull Request (merged)
   - Content-Type: `application/json`

4. **Set Up GCS Notifications**
   ```bash
   # Configure Pub/Sub notifications for SBOM uploads
   gsutil notification create -t sbom-uploads -f json \
     -e OBJECT_FINALIZE \
     -p "sbom/" \
     gs://compliance-evidence-ssdf
   ```

5. **Initialize Database Schema**
   ```sql
   -- Create tables
   CREATE TABLE evidence_registry (
     evidence_id VARCHAR(255) PRIMARY KEY,
     repository VARCHAR(255),
     commit_sha VARCHAR(64),
     branch VARCHAR(255),
     timestamp TIMESTAMP,
     workflow_name VARCHAR(255),
     actor VARCHAR(255),
     ssdf_practices JSONB,
     evidence_path TEXT,
     manifest JSONB,
     created_at TIMESTAMP DEFAULT NOW(),
     updated_at TIMESTAMP
   );

   CREATE TABLE sbom_components (
     sbom_id VARCHAR(255),
     name VARCHAR(255),
     version VARCHAR(255),
     type VARCHAR(50),
     purl TEXT,
     licenses JSONB,
     cpe TEXT,
     last_seen TIMESTAMP,
     metadata JSONB,
     PRIMARY KEY (sbom_id, name, version)
   );

   CREATE TABLE vulnerability_tracking (
     cve_id VARCHAR(50),
     repository VARCHAR(255),
     branch VARCHAR(255),
     severity VARCHAR(20),
     cvss_score DECIMAL(3,1),
     package_name VARCHAR(255),
     current_version VARCHAR(255),
     fixed_version VARCHAR(255),
     status VARCHAR(20),
     sla_hours INTEGER,
     detection_time TIMESTAMP,
     deadline TIMESTAMP,
     issue_url TEXT,
     scan_id VARCHAR(255),
     metadata JSONB,
     last_seen TIMESTAMP DEFAULT NOW(),
     PRIMARY KEY (cve_id, repository)
   );

   CREATE TABLE vulnerability_evidence (
     scan_id VARCHAR(255) PRIMARY KEY,
     repository VARCHAR(255),
     branch VARCHAR(255),
     commit_sha VARCHAR(64),
     scan_timestamp TIMESTAMP,
     total_vulnerabilities INTEGER,
     critical_count INTEGER,
     high_count INTEGER,
     medium_count INTEGER,
     low_count INTEGER,
     scan_report JSONB,
     created_at TIMESTAMP DEFAULT NOW()
   );

   CREATE TABLE attestation_registry (
     attestation_id VARCHAR(255) PRIMARY KEY,
     repository VARCHAR(255),
     commit_sha VARCHAR(64),
     branch VARCHAR(255),
     attestation_type VARCHAR(50),
     signed BOOLEAN,
     gcs_path TEXT,
     ssdf_practices JSONB,
     compliance_level VARCHAR(50),
     created_at TIMESTAMP DEFAULT NOW(),
     expires_at TIMESTAMP,
     metadata JSONB
   );

   CREATE TABLE sbom_registry (
     sbom_id VARCHAR(255) PRIMARY KEY,
     file_name VARCHAR(255),
     format VARCHAR(50),
     component_count INTEGER,
     vulnerability_summary JSONB,
     license_summary JSONB,
     created_at TIMESTAMP DEFAULT NOW(),
     updated_at TIMESTAMP,
     metadata JSONB
   );

   -- Create indexes
   CREATE INDEX idx_evidence_repo ON evidence_registry(repository);
   CREATE INDEX idx_evidence_timestamp ON evidence_registry(timestamp);
   CREATE INDEX idx_vuln_repo ON vulnerability_tracking(repository);
   CREATE INDEX idx_vuln_status ON vulnerability_tracking(status);
   CREATE INDEX idx_vuln_deadline ON vulnerability_tracking(deadline);
   CREATE INDEX idx_attestation_repo ON attestation_registry(repository);
   ```

6. **Activate Workflows**

   In n8n UI:
   - Open each workflow
   - Click the toggle to activate
   - Verify webhook URLs are accessible

7. **Test Workflows**

   Test each workflow with sample data:

   ```bash
   # Test Evidence Collection
   curl -X POST http://localhost:5678/webhook/gitea-workflow-complete \
     -H "Content-Type: application/json" \
     -d @test-data/workflow-complete.json

   # Test SBOM Management (upload test SBOM to GCS)
   gsutil cp test-data/test-sbom.json \
     gs://compliance-evidence-ssdf/test-repo/2025-01-07/test-sbom.json

   # Test Vulnerability Response
   curl -X POST http://localhost:5678/webhook/security-scan-complete \
     -H "Content-Type: application/json" \
     -d @test-data/scan-results.json

   # Test Attestation Generation
   curl -X POST http://localhost:5678/webhook/build-success-trigger \
     -H "Content-Type: application/json" \
     -d @test-data/build-success.json
   ```

## Configuration Options

### Environment Variables

Set these in n8n environment:

```bash
# n8n Configuration
N8N_WEBHOOK_BASE_URL=https://n8n.example.com
N8N_ENCRYPTION_KEY=your-encryption-key

# PostgreSQL
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres-host
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=compliance_db
DB_POSTGRESDB_USER=n8n_user
DB_POSTGRESDB_PASSWORD=secure_password

# Execution Settings
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
```

### Workflow Variables

Update these in each workflow:

1. **Evidence Collection**:
   - `EVIDENCE_BUCKET`: GCS bucket name
   - `EVIDENCE_RETENTION_DAYS`: Evidence retention period
   - `TOOLS_TIMEOUT`: Tool API timeout (ms)

2. **SBOM Management**:
   - `LICENSE_ALLOWLIST`: Approved licenses
   - `LICENSE_BLOCKLIST`: Prohibited licenses
   - `OUTDATED_THRESHOLD_DAYS`: Dependency age threshold

3. **Vulnerability Response**:
   - `SLA_CRITICAL_HOURS`: Critical vulnerability SLA
   - `SLA_HIGH_HOURS`: High vulnerability SLA
   - `SLA_MEDIUM_HOURS`: Medium vulnerability SLA
   - `PAGERDUTY_ENABLED`: Enable PagerDuty alerts

4. **Attestation Generation**:
   - `SIGNING_KEY_NAME`: Cosign key identifier
   - `ATTESTATION_RETENTION_YEARS`: Archive retention
   - `PDF_GENERATION_ENABLED`: Enable PDF reports

## Monitoring and Maintenance

### Health Checks

Monitor workflow health:
```bash
# Check workflow status
curl http://localhost:5678/api/v1/workflows

# Check recent executions
curl http://localhost:5678/api/v1/executions?limit=10

# Database health
psql -U n8n_user -d compliance_db -c "SELECT COUNT(*) FROM evidence_registry WHERE created_at > NOW() - INTERVAL '24 hours';"
```

### Log Analysis

Important log locations:
- n8n logs: `/var/log/n8n/`
- Execution logs: PostgreSQL `execution_entity` table
- Webhook logs: n8n UI → Executions

### Backup and Recovery

1. **Workflow Backup**:
   ```bash
   # Export all workflows
   n8n export:workflow --all --output=workflows-backup.json
   ```

2. **Database Backup**:
   ```bash
   # Backup PostgreSQL
   pg_dump -U n8n_user -d compliance_db > compliance_db_backup.sql
   ```

3. **GCS Backup**:
   - Enabled via bucket versioning
   - Cross-region replication recommended

## Troubleshooting

### Common Issues

1. **Webhook Not Triggering**
   - Verify webhook URL accessibility
   - Check Gitea webhook delivery logs
   - Ensure n8n is listening on correct port

2. **Authentication Failures**
   - Rotate API keys
   - Verify OAuth2 token refresh
   - Check credential IDs match

3. **Database Connection Issues**
   - Verify PostgreSQL is running
   - Check connection pool settings
   - Review firewall rules

4. **GCS Upload Failures**
   - Verify service account permissions
   - Check bucket quotas
   - Review IAM policies

### Debug Mode

Enable debug logging:
```bash
# n8n debug mode
export N8N_LOG_LEVEL=debug
n8n start
```

## Support and Documentation

- **n8n Documentation**: https://docs.n8n.io
- **SSDF Framework**: https://csrc.nist.gov/Projects/ssdf
- **SLSA Specification**: https://slsa.dev
- **Issues**: Create in Gitea repository

## License

These workflows are provided as-is for SSDF compliance automation.

---
*Generated by DevSecOps Platform - SSDF Compliance Automation*