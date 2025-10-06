# GCP Evidence Collection Framework

Automated evidence collection from Google Cloud Platform for CMMC 2.0 and NIST SP 800-171 Rev. 2 compliance.

## Quick Start

### 1. Prerequisites

- GCP Project with appropriate permissions
- Python 3.11+
- Docker and Docker Compose (for containerized deployment)
- gcloud CLI installed and configured

### 2. Initial Setup

```bash
# Run automated setup script
chmod +x setup-gcp-environment.sh
./setup-gcp-environment.sh

# Or manually configure
cp config/gcp-service-account.json.example config/gcp-service-account.json
# Add your service account credentials

# Edit configuration
nano config/evidence-config.yaml
# Update gcp_project_id, gcs_bucket, etc.
```

### 3. Install Dependencies

```bash
# Python dependencies
pip install -r requirements.txt

# Or use Docker
docker-compose -f docker-compose-collectors.yml build
```

### 4. Run Collectors

**Docker (Recommended)**:
```bash
docker-compose -f docker-compose-collectors.yml up -d
```

**Manual**:
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

### 5. Monitor Collection

```bash
# View logs
tail -f logs/*.log

# Check metrics
curl http://localhost:9090/metrics

# Verify evidence
python3 manifest-generator.py --verify manifests/latest.json
```

## Directory Structure

```
evidence-collection/
├── config/
│   ├── evidence-config.yaml           # Main configuration
│   ├── gcp-service-account.json       # Service account credentials
│   └── gcp-service-account.json.example
├── output/
│   ├── scc/                           # Security Command Center findings
│   ├── asset-inventory/               # Asset configurations
│   ├── iam/                           # IAM evidence
│   ├── encryption/                    # Encryption audit results
│   └── logging/                       # Logging export configs
├── manifests/                         # Evidence manifests with SHA-256 hashes
├── logs/                              # Collector logs
├── schemas/                           # JSON schemas for validation
│   ├── evidence-artifact-schema.json
│   └── manifest-schema.json
├── gcp-scc-collector.py               # Security findings collector
├── gcp-asset-inventory.py             # Asset inventory collector
├── gcp-iam-evidence.py                # IAM evidence collector
├── gcp-encryption-audit.py            # Encryption auditor
├── gcp-logging-export.sh              # Logging export script
├── manifest-generator.py              # Manifest generator/verifier
├── evidence-metrics-exporter.py       # Prometheus metrics
├── docker-compose-collectors.yml      # Docker orchestration
├── Dockerfile.collectors              # Collector container image
├── Dockerfile.metrics                 # Metrics container image
├── requirements.txt                   # Python dependencies
├── setup-gcp-environment.sh           # Automated GCP setup
├── GCP_EVIDENCE_COLLECTION_GUIDE.md   # Detailed documentation
├── EVIDENCE_RETENTION_POLICY.md       # Retention schedules
└── README.md                          # This file
```

## Collectors

| Collector | Purpose | Schedule | Controls |
|-----------|---------|----------|----------|
| **SCC Collector** | Security findings & vulnerabilities | Daily | SI.L2-3.14.1, SI.L2-3.14.2, IR.L2-3.6.1 |
| **Asset Inventory** | Resource configurations | Weekly | CM.L2-3.4.1, CM.L2-3.4.2, SC.L2-3.13.1 |
| **IAM Evidence** | Identity & access management | Weekly | IA.L2-3.5.1, AC.L2-3.1.1, AC.L2-3.1.2 |
| **Encryption Audit** | Key management & encryption | Weekly | SC.L2-3.13.8, SC.L2-3.13.11, SC.L2-3.13.16 |
| **Logging Export** | Audit log configuration | Daily | AU.L2-3.3.1, AU.L2-3.3.2, AU.L2-3.3.5 |
| **Manifest Generator** | Evidence integrity tracking | Daily | All controls |

## Evidence Artifact Format

All evidence follows standardized JSON schema:

```json
{
  "evidence_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2025-10-05T02:00:00Z",
  "control_framework": "CMMC_2.0",
  "control_ids": ["AU.L2-3.3.1", "AU.L2-3.3.2"],
  "collection_method": "automated",
  "source": "gcp_security_command_center",
  "artifact_type": "security_finding",
  "data": { /* evidence data */ },
  "hash": "a3f5c1d2e4b6...",
  "collector_version": "1.0.0",
  "gcp_project": "your-project-id"
}
```

## GCS Bucket Structure

Evidence is automatically exported to GCS with this structure:

```
gs://evidence-{project-id}/
├── YYYY/
│   └── MM/
│       └── DD/
│           ├── control-id/
│           │   └── artifact-{hash}.json
│           └── manifest-{timestamp}.json
├── admin-activity-logs/
├── data-access-logs/
├── security-audit-logs/
└── system-event-logs/
```

## Retention Policies

| Evidence Type | Retention | Storage Class | Immutable |
|--------------|-----------|---------------|-----------|
| Security findings (Critical/High) | 7 years | Multi-region | Yes |
| Admin activity logs | 7 years | Multi-region | Yes |
| IAM configurations | 7 years | Regional | Yes |
| Asset inventory | 7 years | Regional | Yes |
| Data access logs | 90 days | Regional | No |

See [EVIDENCE_RETENTION_POLICY.md](EVIDENCE_RETENTION_POLICY.md) for complete details.

## Monitoring

### Prometheus Metrics

```bash
# Start metrics exporter
docker-compose -f docker-compose-collectors.yml up -d evidence-metrics

# Access metrics
curl http://localhost:9090/metrics
```

**Key metrics**:
- `evidence_files_total` - Total evidence files by source
- `evidence_collection_timestamp` - Last collection time
- `control_coverage_count` - Evidence per control ID
- `manifest_validation_status` - Integrity check status

### Logs

```bash
# View all logs
tail -f logs/*.log

# Specific collector
tail -f logs/gcp-scc-collector.log

# Docker logs
docker-compose -f docker-compose-collectors.yml logs -f
```

## Common Tasks

### Verify Evidence Integrity

```bash
python3 manifest-generator.py --verify manifests/evidence_manifest_2025-10-05.json
```

### Collect Specific Asset Types

```bash
python3 gcp-asset-inventory.py \
  --asset-types compute.googleapis.com/Instance storage.googleapis.com/Bucket \
  --scope project
```

### Filter Security Findings

```bash
python3 gcp-scc-collector.py \
  --filter 'severity="CRITICAL" AND state="ACTIVE"' \
  --max-findings 100
```

### Manual Logging Export

```bash
bash gcp-logging-export.sh
```

## Troubleshooting

### Permission Errors

```bash
# Check service account roles
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SA_EMAIL}"

# Test authentication
gcloud auth activate-service-account --key-file=config/gcp-service-account.json
```

### No Evidence Collected

1. Check API enablement: `gcloud services list --enabled`
2. Review logs: `tail -f logs/gcp-scc-collector.log`
3. Test manually: `python3 gcp-scc-collector.py --config config/evidence-config.yaml`

### Hash Verification Fails

1. Check file modifications
2. Regenerate manifest: `python3 manifest-generator.py`
3. Review file permissions

## Integration

### n8n Workflows

Collectors can be triggered via n8n for event-driven collection. See [N8N_WORKFLOW_AUTOMATIONS.json](../N8N_WORKFLOW_AUTOMATIONS.json).

### CI/CD Integration

Add to Gitea CI pipeline:

```yaml
evidence_collection:
  stage: compliance
  script:
    - docker-compose -f evidence-collection/docker-compose-collectors.yml up -d
    - python3 evidence-collection/manifest-generator.py
  artifacts:
    paths:
      - evidence-collection/manifests/
```

## Documentation

- [GCP_EVIDENCE_COLLECTION_GUIDE.md](GCP_EVIDENCE_COLLECTION_GUIDE.md) - Complete deployment guide
- [EVIDENCE_RETENTION_POLICY.md](EVIDENCE_RETENTION_POLICY.md) - Retention schedules and procedures
- [CONTROL_MAPPING_MATRIX.md](../CONTROL_MAPPING_MATRIX.md) - Control-to-evidence mappings

## Security Considerations

1. **Service Account Keys**: Rotate every 90 days
2. **Evidence Integrity**: Always verify SHA-256 hashes
3. **Access Control**: Restrict access to evidence directories
4. **Retention Locking**: Lock GCS retention in production
5. **Audit Logging**: Enable for all evidence access

## Support

For issues or questions:
- Review collector logs in `logs/` directory
- Check Prometheus metrics at http://localhost:9090/metrics
- Consult [GCP_EVIDENCE_COLLECTION_GUIDE.md](GCP_EVIDENCE_COLLECTION_GUIDE.md)
- Review GCP audit logs for API errors

## Version

**Current Version**: 1.0.0
**Release Date**: 2025-10-05
**Compatible With**: CMMC 2.0, NIST SP 800-171 Rev. 2

## License

Internal use only - Proprietary

---

For detailed instructions, see [GCP_EVIDENCE_COLLECTION_GUIDE.md](GCP_EVIDENCE_COLLECTION_GUIDE.md)
