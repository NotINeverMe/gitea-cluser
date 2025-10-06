# DevSecOps Evidence Collection Framework
## GCP-Integrated Compliance Evidence Management

### EVIDENCE COLLECTION ARCHITECTURE

```yaml
evidence_pipeline:
  ingestion:
    sources:
      - gitea_api: Repository events, commits, PRs
      - ci_cd_logs: Pipeline executions, test results
      - security_scanners: Vulnerability reports, scan logs
      - gcp_apis: Cloud asset inventory, security findings
      - monitoring_stack: Metrics, logs, traces
      - incident_response: Tickets, resolutions

  processing:
    normalization:
      - format: Convert to common JSON schema
      - timestamp: UTC ISO 8601 standardization
      - classification: Map to control families

    enrichment:
      - control_mapping: Link to CMMC/NIST controls
      - risk_scoring: Calculate impact and likelihood
      - context_addition: Add metadata and relationships

    validation:
      - schema_check: Validate against JSON schemas
      - completeness: Ensure required fields present
      - integrity: Calculate and verify hashes

  storage:
    immediate:
      - location: Cloud Firestore
      - retention: 90 days
      - access: Real-time queries

    archive:
      - location: Cloud Storage (Archive class)
      - retention: 7 years
      - compliance: WORM (Write Once Read Many)

    backup:
      - location: Cross-region replication
      - encryption: Customer-managed keys
      - versioning: Enabled with 30-day retention
```

### GCP EVIDENCE SOURCES

#### 1. Security Command Center Integration

```python
# evidence_collector_scc.py
from google.cloud import securitycenter
from google.cloud import storage
import hashlib
import json
from datetime import datetime, timezone

class SCCEvidenceCollector:
    def __init__(self, project_id, organization_id):
        self.project_id = project_id
        self.org_id = organization_id
        self.scc_client = securitycenter.SecurityCenterClient()
        self.storage_client = storage.Client()
        self.evidence_bucket = "compliance-evidence-store"

    def collect_findings(self):
        """Collect security findings from SCC"""
        org_name = f"organizations/{self.org_id}"

        # Query for all active findings
        findings = self.scc_client.list_findings(
            request={
                "parent": f"{org_name}/sources/-",
                "filter": 'state="ACTIVE"'
            }
        )

        evidence_records = []
        for finding in findings:
            evidence = self.process_finding(finding)
            evidence_records.append(evidence)
            self.store_evidence(evidence)

        return evidence_records

    def process_finding(self, finding):
        """Process SCC finding into evidence record"""
        evidence = {
            "id": hashlib.sha256(finding.name.encode()).hexdigest()[:16],
            "source": "gcp_security_command_center",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "finding": {
                "name": finding.name,
                "category": finding.category,
                "severity": finding.severity.name,
                "state": finding.state.name,
                "resource": finding.resource_name
            },
            "control_mappings": self.map_to_controls(finding),
            "evidence_type": "automated_scan",
            "hash": None  # Will be calculated after serialization
        }

        # Calculate hash
        evidence_str = json.dumps(evidence, sort_keys=True, default=str)
        evidence["hash"] = hashlib.sha256(evidence_str.encode()).hexdigest()

        return evidence

    def map_to_controls(self, finding):
        """Map SCC findings to CMMC/NIST controls"""
        control_mapping = {
            "COMPUTE_FIREWALL": ["SC.L2-3.13.1", "SC.L2-3.13.5"],
            "KMS_KEY_ROTATION": ["SC.L2-3.13.16", "SC.L2-3.13.11"],
            "STORAGE_BUCKET_ACL": ["AC.L2-3.1.1", "AC.L2-3.1.3"],
            "IAM_POLICY": ["AC.L2-3.1.5", "IA.L2-3.5.3"],
            "LOGGING_DISABLED": ["AU.L2-3.3.1", "AU.L2-3.3.2"],
            "SQL_PUBLIC_IP": ["SC.L2-3.13.5", "CM.L2-3.4.6"]
        }

        controls = []
        for category_key, control_list in control_mapping.items():
            if category_key in finding.category.upper():
                controls.extend(control_list)

        return controls

    def store_evidence(self, evidence):
        """Store evidence in GCS with immutability"""
        bucket = self.storage_client.bucket(self.evidence_bucket)

        # Create blob with evidence ID and timestamp
        blob_name = f"scc/{evidence['id']}/{evidence['timestamp']}.json"
        blob = bucket.blob(blob_name)

        # Set retention and metadata
        blob.metadata = {
            "evidence_id": evidence["id"],
            "source": "scc",
            "hash": evidence["hash"],
            "controls": ",".join(evidence["control_mappings"])
        }

        # Upload with retention lock
        blob.upload_from_string(
            json.dumps(evidence, indent=2),
            content_type="application/json"
        )

        # Set retention (7 years for compliance)
        blob.retention_expiration_time = datetime.now(timezone.utc).replace(
            year=datetime.now().year + 7
        )
```

#### 2. Cloud Asset Inventory Integration

```python
# evidence_collector_cai.py
from google.cloud import asset_v1
from google.cloud import bigquery
import pandas as pd

class CAIEvidenceCollector:
    def __init__(self, project_id):
        self.project_id = project_id
        self.asset_client = asset_v1.AssetServiceClient()
        self.bq_client = bigquery.Client()
        self.dataset_id = "compliance_evidence"

    def export_asset_inventory(self):
        """Export asset inventory for compliance evidence"""
        parent = f"projects/{self.project_id}"

        # Configure export to BigQuery
        output_config = asset_v1.OutputConfig(
            bigquery_destination=asset_v1.BigQueryDestination(
                dataset=f"projects/{self.project_id}/datasets/{self.dataset_id}",
                table="asset_inventory",
                partition_spec=asset_v1.PartitionSpec(
                    partition_key=asset_v1.PartitionSpec.PartitionKey.REQUEST_TIME
                ),
                force=True
            )
        )

        # Export all asset types
        request = asset_v1.ExportAssetsRequest(
            parent=parent,
            content_type=asset_v1.ContentType.RESOURCE,
            output_config=output_config,
            asset_types=[
                "compute.googleapis.com/Instance",
                "storage.googleapis.com/Bucket",
                "iam.googleapis.com/ServiceAccount",
                "cloudkms.googleapis.com/CryptoKey",
                "compute.googleapis.com/Firewall",
                "compute.googleapis.com/Network"
            ]
        )

        operation = self.asset_client.export_assets(request=request)
        result = operation.result()

        return self.process_asset_export()

    def process_asset_export(self):
        """Process exported assets for compliance evidence"""
        query = """
        SELECT
            name,
            asset_type,
            resource.data as configuration,
            update_time,
            -- Extract specific compliance-relevant fields
            JSON_EXTRACT_SCALAR(resource.data, '$.encryptionKey.kmsKeyName') as encryption_key,
            JSON_EXTRACT_SCALAR(resource.data, '$.iamConfiguration.publicAccessPrevention') as public_access,
            JSON_EXTRACT_SCALAR(resource.data, '$.logging.logBucket') as logging_enabled
        FROM
            `{}.{}.asset_inventory`
        WHERE
            DATE(update_time) = CURRENT_DATE()
        """.format(self.project_id, self.dataset_id)

        df = self.bq_client.query(query).to_dataframe()

        # Generate compliance evidence
        evidence_records = []
        for _, asset in df.iterrows():
            evidence = self.generate_asset_evidence(asset)
            evidence_records.append(evidence)

        return evidence_records

    def generate_asset_evidence(self, asset):
        """Generate evidence record from asset"""
        evidence = {
            "asset_name": asset['name'],
            "asset_type": asset['asset_type'],
            "compliance_checks": {
                "encryption_enabled": bool(asset['encryption_key']),
                "public_access_prevented": asset['public_access'] == 'enforced',
                "logging_enabled": bool(asset['logging_enabled'])
            },
            "last_modified": asset['update_time'].isoformat(),
            "control_attestations": []
        }

        # Map to controls based on compliance checks
        if evidence['compliance_checks']['encryption_enabled']:
            evidence['control_attestations'].append("SC.L2-3.13.16")
            evidence['control_attestations'].append("SC.L2-3.13.11")

        if evidence['compliance_checks']['public_access_prevented']:
            evidence['control_attestations'].append("AC.L2-3.1.20")
            evidence['control_attestations'].append("SC.L2-3.13.5")

        if evidence['compliance_checks']['logging_enabled']:
            evidence['control_attestations'].append("AU.L2-3.3.1")

        return evidence
```

#### 3. Cloud Logging Evidence Collection

```python
# evidence_collector_logging.py
from google.cloud import logging_v2
from google.cloud import pubsub_v1
import re

class LoggingEvidenceCollector:
    def __init__(self, project_id):
        self.project_id = project_id
        self.logging_client = logging_v2.Client()
        self.pubsub_client = pubsub_v1.PublisherClient()
        self.topic_path = f"projects/{project_id}/topics/compliance-events"

    def setup_log_sinks(self):
        """Create log sinks for compliance-relevant events"""
        sinks = [
            {
                "name": "iam-changes-sink",
                "filter": 'protoPayload.methodName=~"^(Create|Update|Delete|Set).*Policy"',
                "description": "IAM policy changes for AC controls"
            },
            {
                "name": "data-access-sink",
                "filter": 'protoPayload.authorizationInfo.permission=~"storage.objects.(get|create|delete)"',
                "description": "Data access events for AU controls"
            },
            {
                "name": "security-events-sink",
                "filter": 'severity>=WARNING AND resource.type="gce_instance"',
                "description": "Security events for SI controls"
            },
            {
                "name": "config-changes-sink",
                "filter": 'protoPayload.methodName=~"compute.*.update"',
                "description": "Configuration changes for CM controls"
            }
        ]

        for sink_config in sinks:
            sink = logging_v2.Sink(
                name=sink_config["name"],
                filter_=sink_config["filter"],
                destination=f"pubsub.googleapis.com/{self.topic_path}"
            )

            try:
                self.logging_client.sink(self.project_id, sink.name)
            except:
                self.logging_client.create_sink(
                    parent=f"projects/{self.project_id}",
                    sink=sink
                )

    def process_log_entry(self, log_entry):
        """Process log entry for compliance evidence"""
        evidence = {
            "log_id": log_entry.insert_id,
            "timestamp": log_entry.timestamp.isoformat(),
            "severity": log_entry.severity,
            "resource": {
                "type": log_entry.resource.type,
                "labels": dict(log_entry.resource.labels)
            },
            "operation": {
                "producer": log_entry.log_name,
                "method": self.extract_method(log_entry)
            },
            "principal": self.extract_principal(log_entry),
            "control_evidence": self.map_log_to_controls(log_entry)
        }

        return evidence

    def extract_method(self, log_entry):
        """Extract method name from log entry"""
        if hasattr(log_entry, 'proto_payload'):
            return log_entry.proto_payload.get('methodName', 'unknown')
        return 'unknown'

    def extract_principal(self, log_entry):
        """Extract principal/user from log entry"""
        if hasattr(log_entry, 'proto_payload'):
            auth_info = log_entry.proto_payload.get('authenticationInfo', {})
            return auth_info.get('principalEmail', 'system')
        return 'unknown'

    def map_log_to_controls(self, log_entry):
        """Map log events to compliance controls"""
        control_patterns = {
            r".*Policy$": ["AC.L2-3.1.1", "AC.L2-3.1.5"],
            r".*Firewall.*": ["SC.L2-3.13.1", "SC.L2-3.13.5"],
            r".*ServiceAccount.*": ["IA.L2-3.5.3", "IA.L2-3.5.4"],
            r".*Backup.*": ["CP.L2-3.11.1", "CP.L2-3.11.2"],
            r".*Encryption.*": ["SC.L2-3.13.16", "SC.L2-3.13.11"],
            r".*Delete.*": ["AU.L2-3.3.1", "CM.L2-3.4.3"]
        }

        method = self.extract_method(log_entry)
        controls = []

        for pattern, control_list in control_patterns.items():
            if re.match(pattern, method):
                controls.extend(control_list)

        return list(set(controls))  # Remove duplicates
```

### EVIDENCE MANIFEST GENERATION

```python
# evidence_manifest.py
import json
import hashlib
from datetime import datetime, timezone
from google.cloud import firestore
from google.cloud import storage

class EvidenceManifest:
    def __init__(self, project_id):
        self.project_id = project_id
        self.db = firestore.Client()
        self.storage_client = storage.Client()
        self.manifest_collection = "evidence_manifests"

    def generate_manifest(self, start_date, end_date, frameworks=None):
        """Generate evidence manifest for date range"""
        frameworks = frameworks or ["CMMC_2.0", "NIST_800-171_Rev2"]

        manifest = {
            "manifest_id": self.generate_manifest_id(),
            "created": datetime.now(timezone.utc).isoformat(),
            "period": {
                "start": start_date.isoformat(),
                "end": end_date.isoformat()
            },
            "frameworks": frameworks,
            "evidence_count": 0,
            "control_coverage": {},
            "evidence_entries": [],
            "integrity": {
                "hash": None,
                "signature": None
            }
        }

        # Collect evidence entries
        evidence_refs = self.collect_evidence_references(start_date, end_date)

        for ref in evidence_refs:
            entry = self.create_manifest_entry(ref)
            manifest["evidence_entries"].append(entry)
            manifest["evidence_count"] += 1

            # Update control coverage
            for control in entry.get("controls", []):
                if control not in manifest["control_coverage"]:
                    manifest["control_coverage"][control] = 0
                manifest["control_coverage"][control] += 1

        # Calculate integrity hash
        manifest_str = json.dumps(manifest, sort_keys=True, default=str)
        manifest["integrity"]["hash"] = hashlib.sha256(manifest_str.encode()).hexdigest()

        # Store manifest
        self.store_manifest(manifest)

        return manifest

    def generate_manifest_id(self):
        """Generate unique manifest ID"""
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
        random_hex = hashlib.sha256(timestamp.encode()).hexdigest()[:8]
        return f"MANIFEST-{timestamp}-{random_hex}"

    def collect_evidence_references(self, start_date, end_date):
        """Collect all evidence references for period"""
        query = self.db.collection("evidence_records") \
            .where("timestamp", ">=", start_date) \
            .where("timestamp", "<=", end_date) \
            .order_by("timestamp")

        return query.stream()

    def create_manifest_entry(self, evidence_ref):
        """Create manifest entry for evidence"""
        evidence = evidence_ref.to_dict()

        return {
            "evidence_id": evidence.get("id"),
            "timestamp": evidence.get("timestamp"),
            "source": evidence.get("source"),
            "type": evidence.get("evidence_type"),
            "controls": evidence.get("control_mappings", []),
            "storage_location": evidence.get("storage_path"),
            "hash": evidence.get("hash"),
            "verified": self.verify_evidence_integrity(evidence)
        }

    def verify_evidence_integrity(self, evidence):
        """Verify evidence hasn't been tampered with"""
        try:
            # Retrieve stored evidence
            bucket_name = "compliance-evidence-store"
            blob_path = evidence.get("storage_path")

            bucket = self.storage_client.bucket(bucket_name)
            blob = bucket.blob(blob_path)

            # Download and verify hash
            content = blob.download_as_text()
            calculated_hash = hashlib.sha256(content.encode()).hexdigest()

            return calculated_hash == evidence.get("hash")
        except Exception:
            return False

    def store_manifest(self, manifest):
        """Store manifest in Firestore and GCS"""
        # Store in Firestore for querying
        doc_ref = self.db.collection(self.manifest_collection) \
            .document(manifest["manifest_id"])
        doc_ref.set(manifest)

        # Archive in GCS for long-term retention
        bucket = self.storage_client.bucket("compliance-manifests")
        blob = bucket.blob(f"{manifest['manifest_id']}.json")

        blob.metadata = {
            "manifest_id": manifest["manifest_id"],
            "period_start": manifest["period"]["start"],
            "period_end": manifest["period"]["end"],
            "hash": manifest["integrity"]["hash"]
        }

        blob.upload_from_string(
            json.dumps(manifest, indent=2),
            content_type="application/json"
        )

        # Set retention
        blob.retention_expiration_time = datetime.now(timezone.utc).replace(
            year=datetime.now().year + 7
        )

    def export_for_audit(self, manifest_id, output_format="pdf"):
        """Export manifest for auditor review"""
        # Retrieve manifest
        doc_ref = self.db.collection(self.manifest_collection) \
            .document(manifest_id)
        manifest = doc_ref.get().to_dict()

        if output_format == "pdf":
            return self.generate_pdf_report(manifest)
        elif output_format == "csv":
            return self.generate_csv_export(manifest)
        else:
            return json.dumps(manifest, indent=2)

    def generate_pdf_report(self, manifest):
        """Generate PDF report of evidence manifest"""
        # Implementation would use reportlab or similar
        pass

    def generate_csv_export(self, manifest):
        """Generate CSV export of evidence entries"""
        import csv
        import io

        output = io.StringIO()
        writer = csv.writer(output)

        # Headers
        writer.writerow([
            "Evidence ID", "Timestamp", "Source", "Type",
            "Controls", "Location", "Hash", "Verified"
        ])

        # Data
        for entry in manifest["evidence_entries"]:
            writer.writerow([
                entry["evidence_id"],
                entry["timestamp"],
                entry["source"],
                entry["type"],
                ";".join(entry["controls"]),
                entry["storage_location"],
                entry["hash"],
                entry["verified"]
            ])

        return output.getvalue()
```

### EVIDENCE COLLECTION AUTOMATION

```bash
#!/bin/bash
# evidence_collection.sh - Automated evidence collection script

# Configuration
PROJECT_ID="your-gcp-project"
BUCKET_NAME="compliance-evidence-store"
MANIFEST_BUCKET="compliance-manifests"

# Function to collect all evidence sources
collect_all_evidence() {
    echo "[$(date)] Starting evidence collection..."

    # Collect from Security Command Center
    python3 evidence_collector_scc.py \
        --project-id "$PROJECT_ID" \
        --output-bucket "$BUCKET_NAME"

    # Collect from Cloud Asset Inventory
    python3 evidence_collector_cai.py \
        --project-id "$PROJECT_ID" \
        --export-dataset "compliance_evidence"

    # Process Cloud Logging
    python3 evidence_collector_logging.py \
        --project-id "$PROJECT_ID" \
        --start-time "$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S)Z"

    # Collect CI/CD evidence
    collect_cicd_evidence

    # Collect security scan results
    collect_security_scans

    echo "[$(date)] Evidence collection complete"
}

# Function to collect CI/CD evidence
collect_cicd_evidence() {
    # Gitea API calls
    curl -H "Authorization: token $GITEA_TOKEN" \
        https://gitea.example.com/api/v1/repos/org/repo/actions/runs \
        | jq '.[] | {id: .id, status: .status, conclusion: .conclusion}' \
        > /tmp/cicd_runs.json

    # Process and store
    python3 -c "
import json
import hashlib
from datetime import datetime

with open('/tmp/cicd_runs.json') as f:
    runs = json.load(f)

for run in runs:
    evidence = {
        'source': 'gitea_cicd',
        'timestamp': datetime.utcnow().isoformat(),
        'run_id': run['id'],
        'status': run['status'],
        'compliance_gates': run.get('annotations', {}).get('security_gates', [])
    }

    # Store evidence
    print(json.dumps(evidence))
"
}

# Function to collect security scan results
collect_security_scans() {
    # SonarQube results
    curl -u "$SONAR_TOKEN:" \
        "https://sonar.example.com/api/measures/component?component=project&metricKeys=security_rating,vulnerabilities" \
        > /tmp/sonar_results.json

    # Trivy scan results
    trivy fs --format json --output /tmp/trivy_results.json /

    # Process and store all scan results
    python3 process_scan_results.py \
        --sonar /tmp/sonar_results.json \
        --trivy /tmp/trivy_results.json \
        --output-bucket "$BUCKET_NAME"
}

# Function to generate daily manifest
generate_daily_manifest() {
    echo "[$(date)] Generating daily evidence manifest..."

    python3 evidence_manifest.py \
        --project-id "$PROJECT_ID" \
        --start-date "$(date -u -d '1 day ago' +%Y-%m-%d)" \
        --end-date "$(date -u +%Y-%m-%d)" \
        --frameworks "CMMC_2.0,NIST_800-171_Rev2" \
        --output-bucket "$MANIFEST_BUCKET"

    echo "[$(date)] Manifest generation complete"
}

# Function to verify evidence integrity
verify_evidence_integrity() {
    echo "[$(date)] Verifying evidence integrity..."

    gsutil ls -l "gs://$BUCKET_NAME/**" | while read -r line; do
        file_path=$(echo "$line" | awk '{print $3}')
        stored_hash=$(gsutil stat "$file_path" | grep "Hash (md5)" | awk '{print $3}')

        # Download and verify
        gsutil cp "$file_path" /tmp/verify_temp
        calculated_hash=$(md5sum /tmp/verify_temp | awk '{print $1}')

        if [ "$stored_hash" != "$calculated_hash" ]; then
            echo "INTEGRITY FAILURE: $file_path"
            # Send alert
            curl -X POST https://alerts.example.com/webhook \
                -d "{\"alert\": \"Evidence integrity failure\", \"file\": \"$file_path\"}"
        fi
    done

    echo "[$(date)] Integrity verification complete"
}

# Main execution
main() {
    case "$1" in
        collect)
            collect_all_evidence
            ;;
        manifest)
            generate_daily_manifest
            ;;
        verify)
            verify_evidence_integrity
            ;;
        all)
            collect_all_evidence
            generate_daily_manifest
            verify_evidence_integrity
            ;;
        *)
            echo "Usage: $0 {collect|manifest|verify|all}"
            exit 1
            ;;
    esac
}

main "$@"
```

### EVIDENCE RETENTION POLICIES

| Evidence Type | Retention Period | Storage Class | Encryption | Access Control |
|--------------|------------------|---------------|------------|----------------|
| Security Scans | 1 year | Standard | AES-256 | Read-only after 30 days |
| Audit Logs | 3 years | Nearline | CMEK | Immutable after creation |
| Compliance Reports | 7 years | Archive | CMEK + HSM | Restricted access |
| Incident Records | 7 years | Archive | CMEK + HSM | Legal hold capable |
| Configuration Baselines | Indefinite | Standard | AES-256 | Version controlled |
| Access Reviews | 3 years | Nearline | CMEK | Audit trail required |
| Vulnerability Reports | 2 years | Standard | AES-256 | Redaction supported |
| Change Records | 7 years | Archive | CMEK | Immutable |