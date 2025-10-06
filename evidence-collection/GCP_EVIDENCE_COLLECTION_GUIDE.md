# GCP Evidence Collection Framework - Deployment & Operations Guide

## Overview

This framework provides automated evidence collection from Google Cloud Platform (GCP) for CMMC 2.0 and NIST SP 800-171 Rev. 2 compliance. It integrates with the Gitea DevSecOps platform to provide continuous compliance monitoring and audit trail generation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GCP Evidence Collection                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ SCC Findings │  │Asset Inventory│  │ IAM Evidence │          │
│  │  Collector   │  │   Collector   │  │  Collector   │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                   │
│  ┌──────▼───────┐  ┌──────▼───────┐  ┌──────▼───────┐          │
│  │ Encryption   │  │   Logging    │  │  Manifest    │          │
│  │   Auditor    │  │   Exporter   │  │  Generator   │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                   │
│         └──────────────────┼──────────────────┘                  │
│                            ▼                                      │
│                   ┌────────────────┐                             │
│                   │  GCS Bucket    │                             │
│                   │  (Evidence)    │                             │
│                   └────────┬───────┘                             │
│                            │                                      │
│                   ┌────────▼───────┐                             │
│                   │  Prometheus    │                             │
│                   │  Metrics       │                             │
│                   └────────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. GCP Service Account Configuration

Create a dedicated service account with minimal required permissions:

```bash
# Set variables
export PROJECT_ID="your-project-id"
export SA_NAME="evidence-collector"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
gcloud iam service-accounts create ${SA_NAME} \
    --display-name="Evidence Collection Service Account" \
    --description="Automated evidence collection for compliance" \
    --project=${PROJECT_ID}

# Grant required roles at PROJECT level
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/securitycenter.findingsViewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/cloudasset.viewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/logging.viewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.securityReviewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/cloudkms.viewer"

# Grant Storage Object Creator for GCS uploads
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.objectCreator"

# Generate and download key
gcloud iam service-accounts keys create gcp-service-account.json \
    --iam-account=${SA_EMAIL} \
    --project=${PROJECT_ID}
```

### 2. GCS Bucket Setup

Create evidence storage bucket with retention policies:

```bash
# Create bucket with uniform bucket-level access
gsutil mb -p ${PROJECT_ID} -l us-central1 gs://evidence-${PROJECT_ID}/

# Enable versioning
gsutil versioning set on gs://evidence-${PROJECT_ID}/

# Set retention policy (7 years = 2555 days)
gsutil retention set 7y gs://evidence-${PROJECT_ID}/

# IMPORTANT: Lock retention policy (irreversible - do this after testing!)
# gsutil retention lock gs://evidence-${PROJECT_ID}/

# Set lifecycle policy
cat > lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 2555,
          "matchesPrefix": ["admin-activity-logs/", "security-audit-logs/"]
        }
      },
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "matchesPrefix": ["data-access-logs/"]
        }
      }
    ]
  }
}
EOF

gsutil lifecycle set lifecycle.json gs://evidence-${PROJECT_ID}/

# Enable uniform bucket-level access
gsutil uniformbucketlevelaccess set on gs://evidence-${PROJECT_ID}/
```

### 3. Enable Required APIs

```bash
gcloud services enable securitycenter.googleapis.com \
    cloudasset.googleapis.com \
    logging.googleapis.com \
    iam.googleapis.com \
    cloudkms.googleapis.com \
    compute.googleapis.com \
    storage.googleapis.com \
    --project=${PROJECT_ID}
```

## Installation

### Method 1: Docker Compose (Recommended)

1. **Clone or copy the evidence-collection directory**

```bash
cd /home/notme/Desktop/gitea/evidence-collection
```

2. **Configure settings**

```bash
# Copy service account key
cp /path/to/gcp-service-account.json config/gcp-service-account.json

# Edit configuration
nano config/evidence-config.yaml
```

Update the following fields:
- `gcp_project_id`: Your GCP project ID
- `gcp_organization_id`: Your GCP organization ID (if applicable)
- `gcs_bucket`: Your evidence bucket name
- `google_chat_webhook`: Your notification webhook (optional)

3. **Create required directories**

```bash
mkdir -p output/{scc,asset-inventory,iam,encryption,logging}
mkdir -p logs manifests
chmod 755 output logs manifests
```

4. **Build and start collectors**

```bash
# Build images
docker-compose -f docker-compose-collectors.yml build

# Start all collectors
docker-compose -f docker-compose-collectors.yml up -d

# Check status
docker-compose -f docker-compose-collectors.yml ps

# View logs
docker-compose -f docker-compose-collectors.yml logs -f
```

### Method 2: Direct Python Installation

1. **Install Python dependencies**

```bash
pip install -r requirements.txt
```

2. **Configure environment**

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/home/notme/Desktop/gitea/evidence-collection/config/gcp-service-account.json"
```

3. **Run collectors manually**

```bash
# Security Command Center
python3 gcp-scc-collector.py --config config/evidence-config.yaml

# Asset Inventory
python3 gcp-asset-inventory.py --config config/evidence-config.yaml

# IAM Evidence
python3 gcp-iam-evidence.py --config config/evidence-config.yaml

# Encryption Audit
python3 gcp-encryption-audit.py --config config/evidence-config.yaml

# Logging Export
bash gcp-logging-export.sh

# Generate Manifest
python3 manifest-generator.py --evidence-dir output/
```

### Method 3: Systemd Timers (Production)

Create systemd service files for each collector:

```bash
# Create service file
sudo nano /etc/systemd/system/gcp-scc-collector.service
```

```ini
[Unit]
Description=GCP Security Command Center Evidence Collector
After=network.target

[Service]
Type=oneshot
User=evidence
Group=evidence
WorkingDirectory=/home/notme/Desktop/gitea/evidence-collection
Environment="GOOGLE_APPLICATION_CREDENTIALS=/home/notme/Desktop/gitea/evidence-collection/config/gcp-service-account.json"
ExecStart=/usr/bin/python3 /home/notme/Desktop/gitea/evidence-collection/gcp-scc-collector.py --config config/evidence-config.yaml

[Install]
WantedBy=multi-user.target
```

```bash
# Create timer file
sudo nano /etc/systemd/system/gcp-scc-collector.timer
```

```ini
[Unit]
Description=Run GCP SCC Collector Daily
Requires=gcp-scc-collector.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable gcp-scc-collector.timer
sudo systemctl start gcp-scc-collector.timer
```

## Collector Details

### 1. Security Command Center Collector

**Purpose**: Collects security findings and vulnerabilities
**Schedule**: Daily at 2 AM
**Output**: `output/scc/`
**Controls**: SI.L2-3.14.1, SI.L2-3.14.2, SI.L2-3.14.3, IR.L2-3.6.1

**Command-line options**:
```bash
python3 gcp-scc-collector.py \
    --config config/evidence-config.yaml \
    --filter 'state="ACTIVE" AND severity="HIGH"' \
    --max-findings 500
```

### 2. Asset Inventory Collector

**Purpose**: Snapshots resource configurations
**Schedule**: Weekly (Sunday at 3 AM)
**Output**: `output/asset-inventory/`
**Controls**: CM.L2-3.4.1, CM.L2-3.4.2, SC.L2-3.13.1, AC.L2-3.1.1

**Command-line options**:
```bash
python3 gcp-asset-inventory.py \
    --config config/evidence-config.yaml \
    --asset-types compute.googleapis.com/Instance storage.googleapis.com/Bucket \
    --scope organization \
    --no-iam
```

### 3. IAM Evidence Collector

**Purpose**: Collects user, service account, and role configurations
**Schedule**: Weekly (Monday at 4 AM)
**Output**: `output/iam/`
**Controls**: IA.L2-3.5.1, IA.L2-3.5.2, AC.L2-3.1.1, AC.L2-3.1.2

**Key evidence**:
- Service accounts and key age
- Role bindings and permissions
- Custom roles
- MFA enforcement status
- Key rotation compliance

### 4. Encryption Auditor

**Purpose**: Audits encryption configuration and key management
**Schedule**: Weekly (Monday at 5 AM)
**Output**: `output/encryption/`
**Controls**: SC.L2-3.13.8, SC.L2-3.13.11, SC.L2-3.13.16

**Key evidence**:
- CMEK key configurations
- Key rotation schedules
- Encryption-at-rest settings
- Key access control policies

### 5. Logging Export Script

**Purpose**: Configures continuous log exports to GCS
**Schedule**: Daily at 1 AM (verifies sinks)
**Output**: `output/logging/` + GCS bucket
**Controls**: AU.L2-3.3.1, AU.L2-3.3.2, AU.L2-3.3.5

**Log types exported**:
- Admin activity logs (365-day retention)
- Data access logs (90-day retention)
- System event logs
- Security audit logs

### 6. Manifest Generator

**Purpose**: Creates integrity manifests with SHA-256 hashes
**Schedule**: Daily after all collectors complete
**Output**: `manifests/`

**Command-line options**:
```bash
# Generate manifest
python3 manifest-generator.py --evidence-dir output/

# Verify integrity
python3 manifest-generator.py --verify manifests/evidence_manifest_2025-10-05_120000.json
```

## Monitoring

### Prometheus Metrics

Access metrics at: `http://localhost:9090/metrics`

**Key metrics**:
- `evidence_files_total`: Total evidence files by source and type
- `evidence_collection_timestamp`: Last collection timestamp per collector
- `evidence_collection_errors_total`: Collection error count
- `control_coverage_count`: Evidence count per control ID
- `manifest_validation_status`: Manifest integrity status

### Grafana Dashboard

Import the provided dashboard configuration:

```bash
# Import dashboard
curl -X POST http://grafana:3000/api/dashboards/db \
    -H "Content-Type: application/json" \
    -d @grafana-dashboard.json
```

## Evidence Artifact Structure

All evidence artifacts follow this JSON schema:

```json
{
  "evidence_id": "uuid-v4",
  "timestamp": "2025-10-05T02:00:00Z",
  "control_framework": "CMMC_2.0",
  "control_ids": ["AU.L2-3.3.1", "AU.L2-3.3.2"],
  "collection_method": "automated",
  "source": "gcp_cloud_logging",
  "artifact_type": "log_export_config",
  "data": { /* collected evidence */ },
  "hash": "sha256-hex-digest",
  "collector_version": "1.0.0",
  "gcp_project": "project-id"
}
```

## Control Mappings

| Control ID | Description | Evidence Sources |
|------------|-------------|------------------|
| AU.L2-3.3.1 | Audit event logging | Cloud Logging exports, SCC findings |
| AU.L2-3.3.2 | Audit log content | Cloud Logging exports |
| AC.L2-3.1.1 | Access control policies | IAM policies, Asset inventory |
| AC.L2-3.1.2 | Account management | IAM evidence, Service accounts |
| IA.L2-3.5.1 | Identifier management | IAM evidence |
| SC.L2-3.13.8 | Cryptographic protection | KMS keys, Encryption audit |
| SC.L2-3.13.16 | Data at rest protection | Encryption audit, Asset configs |
| SI.L2-3.14.1 | Flaw remediation | SCC findings |

Full mapping table: See `CONTROL_MAPPING_MATRIX.md`

## Troubleshooting

### Service Account Permissions

If collectors fail with permission errors:

```bash
# Check service account roles
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${SA_EMAIL}"

# Test authentication
gcloud auth activate-service-account --key-file=config/gcp-service-account.json
gcloud projects describe ${PROJECT_ID}
```

### No Evidence Collected

1. **Check API enablement**:
```bash
gcloud services list --enabled --project=${PROJECT_ID}
```

2. **Verify log output**:
```bash
tail -f logs/gcp-scc-collector.log
```

3. **Run collector manually**:
```bash
python3 gcp-scc-collector.py --config config/evidence-config.yaml
```

### Hash Verification Failures

If manifest verification reports hash mismatches:

1. Check for file modifications
2. Regenerate manifest
3. Review file permissions and ownership

```bash
# Re-verify
python3 manifest-generator.py --verify manifests/latest.json
```

## Maintenance

### Weekly Tasks

- Review collector logs for errors
- Verify evidence collection metrics
- Check GCS bucket storage usage
- Validate manifests

### Monthly Tasks

- Rotate service account keys (if not using Workload Identity)
- Review and update control mappings
- Audit retention policies
- Generate compliance reports

### Quarterly Tasks

- Review and update collector versions
- Audit service account permissions
- Test disaster recovery procedures
- Update documentation

## Security Considerations

1. **Service Account Keys**: Store securely, rotate every 90 days
2. **Evidence Integrity**: Always verify SHA-256 hashes before use
3. **Access Control**: Limit access to evidence directories and GCS bucket
4. **Retention Locking**: Lock GCS retention policy after validation
5. **Audit Logs**: Enable audit logging for evidence collection activities

## Integration with n8n Workflows

The collectors can be triggered via n8n workflows for event-driven collection:

```javascript
// n8n HTTP Request node
{
  "method": "POST",
  "url": "http://evidence-collector:8080/collect",
  "body": {
    "collector": "scc",
    "trigger": "security_event",
    "event_id": "{{$json.event_id}}"
  }
}
```

See `N8N_WORKFLOW_AUTOMATIONS.json` for complete workflow examples.

## Support

For issues or questions:
- Review logs in `logs/` directory
- Check Prometheus metrics
- Consult control mapping documentation
- Review GCP audit logs for API errors

## Version History

- **1.0.0** (2025-10-05): Initial production release
  - All core collectors implemented
  - Manifest generation and verification
  - Prometheus metrics integration
  - Docker containerization
