# Evidence Retention Policy

## Purpose

This document defines retention schedules, storage requirements, and disposal procedures for compliance evidence collected from Google Cloud Platform (GCP) in support of CMMC 2.0 and NIST SP 800-171 Rev. 2 requirements.

## Regulatory Requirements

### CMMC 2.0 Audit Evidence Retention
- **Level 2 Certification**: Evidence must be retained for the duration of certification (3 years) plus 1 year
- **Minimum Retention**: 4 years from collection date
- **Recommended Retention**: 7 years for critical security evidence

### NIST SP 800-171 Requirements
- **AU.L2-3.3.4**: Audit log retention of at least 90 days for data access logs
- **AU.L2-3.3.1**: System audit records retained per organizational retention policy
- **Recommended Practice**: 7-year retention for security audit logs

### Federal Contract Requirements
- **FAR 52.204-21**: Retention of CUI and related records for 3 years after final payment
- **DFARS 252.204-7012**: Cyber incident reporting records for 3 years
- **Recommended Practice**: 7-year retention for all contract-related evidence

## Retention Schedule

### Tier 1: Critical Security Evidence (7 Years)

**Retention Period**: 2555 days (7 years)

**Evidence Types**:
- Security Command Center findings (CRITICAL and HIGH severity)
- Admin activity audit logs
- Security audit logs (IAM changes, KMS operations)
- System event logs
- Asset inventory snapshots
- IAM policy configurations
- Encryption key configurations and rotation records
- Compliance assessment results

**Storage Requirements**:
- GCS bucket with 7-year retention policy
- Immutable storage (WORM) enabled
- Version retention enabled
- Multi-region replication for critical evidence

**GCS Bucket Structure**:
```
gs://evidence-{project-id}/
  ├── admin-activity-logs/YYYY/MM/DD/
  ├── security-audit-logs/YYYY/MM/DD/
  ├── system-event-logs/YYYY/MM/DD/
  ├── scc-findings/YYYY/MM/DD/control-id/
  ├── asset-inventory/YYYY/MM/DD/
  ├── iam-evidence/YYYY/MM/DD/
  └── encryption-audit/YYYY/MM/DD/
```

**Lifecycle Rule**:
```json
{
  "action": {"type": "Delete"},
  "condition": {
    "age": 2555,
    "matchesPrefix": [
      "admin-activity-logs/",
      "security-audit-logs/",
      "system-event-logs/",
      "scc-findings/",
      "asset-inventory/",
      "iam-evidence/",
      "encryption-audit/"
    ]
  }
}
```

### Tier 2: Operational Evidence (2 Years)

**Retention Period**: 730 days (2 years)

**Evidence Types**:
- Security Command Center findings (MEDIUM and LOW severity)
- Change management records
- Configuration baselines
- Vulnerability scan results
- Non-critical asset configurations

**Storage Requirements**:
- GCS bucket with 2-year retention policy
- Standard storage class
- Regional replication

**Lifecycle Rule**:
```json
{
  "action": {"type": "Delete"},
  "condition": {
    "age": 730,
    "matchesPrefix": [
      "operational-evidence/"
    ]
  }
}
```

### Tier 3: Data Access Logs (90 Days)

**Retention Period**: 90 days (minimum per AU.L2-3.3.4)

**Evidence Types**:
- Data access audit logs (Cloud Storage, BigQuery, Cloud SQL)
- Read operations on sensitive data
- Query logs

**Storage Requirements**:
- GCS bucket with 90-day retention policy
- Standard storage class
- Single-region storage

**Lifecycle Rule**:
```json
{
  "action": {"type": "Delete"},
  "condition": {
    "age": 90,
    "matchesPrefix": [
      "data-access-logs/"
    ]
  }
}
```

**Exception**: Data access logs related to security incidents or investigations must be promoted to Tier 1 retention.

### Tier 4: Temporary Working Files (30 Days)

**Retention Period**: 30 days

**Evidence Types**:
- Collector temporary output
- Intermediate processing files
- Non-critical summaries

**Storage Requirements**:
- Local filesystem or standard GCS bucket
- No special retention requirements

**Lifecycle Rule**:
```json
{
  "action": {"type": "Delete"},
  "condition": {
    "age": 30,
    "matchesPrefix": [
      "temp/",
      "working/"
    ]
  }
}
```

## Evidence Manifest Retention

### Master Manifests

**Retention**: Permanent (throughout organization lifetime)

**Contents**:
- SHA-256 hashes of all evidence artifacts
- Collection timestamps
- Control mappings
- File metadata

**Storage**:
- GCS bucket with retention lock
- Multi-region replication
- Backed up to secondary location

**File Naming**:
```
manifests/
  ├── master_manifest_YYYY.json
  ├── master_manifest_YYYY.json.sha256
  └── monthly/
      ├── manifest_YYYY-MM.json
      └── manifest_YYYY-MM.json.sha256
```

### Daily Manifests

**Retention**: Same as evidence tier (typically 7 years)

**Storage**: GCS bucket with corresponding retention policy

## Storage Implementation

### GCS Bucket Configuration

```bash
# Create Tier 1 evidence bucket (7 years)
gsutil mb -p ${PROJECT_ID} -l us-central1 gs://evidence-tier1-${PROJECT_ID}/
gsutil versioning set on gs://evidence-tier1-${PROJECT_ID}/
gsutil retention set 7y gs://evidence-tier1-${PROJECT_ID}/

# CRITICAL: Lock retention policy after validation
# gsutil retention lock gs://evidence-tier1-${PROJECT_ID}/

# Create Tier 3 evidence bucket (90 days)
gsutil mb -p ${PROJECT_ID} -l us-central1 gs://evidence-tier3-${PROJECT_ID}/
gsutil retention set 90d gs://evidence-tier3-${PROJECT_ID}/

# Set lifecycle policies
gsutil lifecycle set lifecycle-tier1.json gs://evidence-tier1-${PROJECT_ID}/
gsutil lifecycle set lifecycle-tier3.json gs://evidence-tier3-${PROJECT_ID}/
```

### Immutable Storage (WORM)

For Tier 1 critical evidence, configure bucket retention lock:

```bash
# Set retention policy
gsutil retention set 7y gs://evidence-tier1-${PROJECT_ID}/

# Lock retention policy (IRREVERSIBLE - test thoroughly first!)
gsutil retention lock gs://evidence-tier1-${PROJECT_ID}/
```

**WARNING**: Retention lock is permanent and cannot be removed. Objects cannot be deleted until retention period expires.

### Multi-Region Replication

For critical evidence requiring disaster recovery:

```bash
# Create multi-region bucket
gsutil mb -p ${PROJECT_ID} -c STANDARD -l US gs://evidence-multi-${PROJECT_ID}/

# Enable turbo replication (optional, for faster geo-redundancy)
gsutil rpo set ASYNC_TURBO gs://evidence-multi-${PROJECT_ID}/
```

## Evidence Integrity Verification

### Hash Verification

All evidence artifacts include SHA-256 hashes for integrity verification:

```bash
# Verify single file
sha256sum output/scc/scc_finding_uuid_2025-10-05.json
cat output/scc/scc_finding_uuid_2025-10-05.json.sha256

# Verify using manifest
python3 manifest-generator.py --verify manifests/evidence_manifest_2025-10-05.json
```

### Scheduled Verification

Run integrity checks monthly:

```bash
# Add to cron
0 0 1 * * /usr/bin/python3 /path/to/manifest-generator.py --verify /path/to/manifests/latest.json
```

## Disposal Procedures

### Automated Disposal (GCS Lifecycle)

Evidence is automatically deleted when retention period expires via GCS lifecycle rules.

**No manual intervention required** for standard retention tiers.

### Manual Disposal (Exception Cases)

For evidence requiring early disposal (e.g., duplicate records, test data):

1. **Document justification** in disposal log
2. **Obtain approval** from compliance officer
3. **Verify no legal hold** applies
4. **Execute disposal**:

```bash
# Document disposal
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - Disposing ${FILE} - Reason: ${REASON} - Approved by: ${APPROVER}" >> disposal-log.txt

# Remove file
gsutil rm gs://evidence-bucket/${FILE}

# Update manifest
python3 manifest-generator.py --remove ${FILE}
```

### Legal Hold

If evidence is subject to legal hold or investigation:

1. **Apply hold** to GCS bucket or specific objects
2. **Document hold** in legal hold register
3. **Prevent lifecycle deletion**:

```bash
# Set legal hold on bucket
gsutil retention event-default set gs://evidence-bucket/

# Set hold on specific object
gsutil retention event set gs://evidence-bucket/path/to/file.json
```

4. **Release hold** only after legal clearance

## Retention Policy Exceptions

### Security Incidents

Evidence related to security incidents must be retained for **7 years minimum**, regardless of original classification.

**Procedure**:
1. Identify all evidence related to incident
2. Copy to Tier 1 storage
3. Tag with incident ID
4. Update manifest with extended retention
5. Document in incident response records

### Litigation/Investigation

Evidence subject to litigation or investigation must be retained until:
- Litigation is resolved
- Investigation is closed
- Legal department provides written clearance

**Procedure**:
1. Apply legal hold to all related evidence
2. Notify legal department
3. Document in legal hold register
4. Do not dispose until written clearance received

### Contract-Specific Requirements

Some contracts may specify longer retention periods. Always retain evidence for the **longer of**:
- Standard retention policy, or
- Contract-specified retention period

## Access and Retrieval

### Evidence Retrieval Process

1. **Request**: Submit evidence retrieval request with justification
2. **Authorization**: Obtain approval from compliance officer or manager
3. **Retrieval**: Access evidence from GCS bucket
4. **Verification**: Verify SHA-256 hash before use
5. **Logging**: Log retrieval in audit trail

```bash
# Retrieve and verify
gsutil cp gs://evidence-bucket/path/to/evidence.json .
sha256sum evidence.json
# Compare with manifest hash
```

### Access Control

Evidence storage buckets must have:
- **Uniform bucket-level access** enabled
- **IAM policies** restricting access to authorized personnel only
- **Audit logging** enabled for all access
- **MFA required** for bucket access

```bash
# Set IAM policy
gsutil iam ch user:auditor@example.com:roles/storage.objectViewer gs://evidence-bucket/

# Enable audit logging (already enabled via Cloud Logging)
# Logs automatically exported to evidence bucket
```

## Compliance Monitoring

### Monthly Reviews

- Verify retention policies are applied correctly
- Check storage usage and forecast capacity
- Review disposal logs
- Validate hash integrity of sample evidence

### Quarterly Audits

- Comprehensive manifest verification
- Review access logs for unauthorized access
- Test evidence retrieval procedures
- Validate backup/replication status

### Annual Assessments

- Review retention policy against current regulations
- Update retention schedules as needed
- Audit complete evidence lifecycle
- Test disaster recovery procedures

## Disaster Recovery

### Backup Strategy

**Tier 1 Evidence**:
- Multi-region GCS buckets (primary)
- Cross-region replication to secondary GCS bucket
- Monthly snapshots to offline storage (for archival)

**Manifests**:
- Replicated to 3 separate GCS buckets
- Exported to offline storage monthly
- Version controlled in Git repository

### Recovery Procedures

In case of evidence loss or corruption:

1. **Assess scope** of loss
2. **Restore from replication** (if recent)
3. **Restore from backup** (if older)
4. **Verify integrity** using manifests
5. **Document recovery** in incident log
6. **Report to compliance** officer

```bash
# Restore from secondary bucket
gsutil -m cp -r gs://evidence-backup-bucket/* gs://evidence-primary-bucket/

# Verify restoration
python3 manifest-generator.py --verify manifests/latest.json
```

## Appendix A: Retention Summary Table

| Evidence Type | Retention Period | Storage Tier | Immutable | Replication |
|--------------|------------------|--------------|-----------|-------------|
| SCC Findings (CRITICAL/HIGH) | 7 years | Tier 1 | Yes | Multi-region |
| Admin Activity Logs | 7 years | Tier 1 | Yes | Multi-region |
| Security Audit Logs | 7 years | Tier 1 | Yes | Multi-region |
| IAM Configurations | 7 years | Tier 1 | Yes | Multi-region |
| Encryption Configs | 7 years | Tier 1 | Yes | Multi-region |
| Asset Inventory | 7 years | Tier 1 | Yes | Regional |
| SCC Findings (MEDIUM/LOW) | 2 years | Tier 2 | No | Regional |
| Data Access Logs | 90 days | Tier 3 | No | Single region |
| Temp Working Files | 30 days | Tier 4 | No | None |
| Master Manifests | Permanent | Tier 1 | Yes | Multi-region |

## Appendix B: GCS Lifecycle Configuration Templates

See configuration files in `config/gcs-lifecycle/`:
- `tier1-lifecycle.json` - 7-year retention
- `tier2-lifecycle.json` - 2-year retention
- `tier3-lifecycle.json` - 90-day retention

## Document Control

- **Version**: 1.0
- **Effective Date**: 2025-10-05
- **Next Review**: 2026-10-05
- **Owner**: DevSecOps Team
- **Approval**: Compliance Officer

---

**Approved by**: _________________________
**Date**: _________________________
