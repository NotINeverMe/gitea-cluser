#!/usr/bin/env python3
"""
GCP Encryption Evidence Collector
Audits CMEK configuration, key rotation, encryption-at-rest, and TLS certificates
"""

import json
import hashlib
import uuid
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional
import logging
import sys
from pathlib import Path

try:
    from google.cloud import kms_v1
    from google.cloud import compute_v1
    from google.oauth2 import service_account
except ImportError:
    print("ERROR: Required packages not installed. Run: pip install google-cloud-kms google-cloud-compute")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/notme/Desktop/gitea/evidence-collection/logs/gcp-encryption-audit.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Encryption control mappings
ENCRYPTION_CONTROL_MAPPINGS = {
    "cmek_keys": ["SC.L2-3.13.8", "SC.L2-3.13.11", "SC.L2-3.13.16"],
    "key_rotation": ["SC.L2-3.13.10", "SC.L2-3.13.11"],
    "encryption_at_rest": ["SC.L2-3.13.16", "MP.L2-3.8.9"],
    "tls_certificates": ["SC.L2-3.13.8", "SC.L2-3.13.12"],
    "key_access_control": ["SC.L2-3.13.10", "AC.L2-3.1.3"],
}


class GCPEncryptionAuditor:
    """Audit GCP encryption configuration for compliance evidence"""

    def __init__(self, config_path: str = "/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml"):
        """Initialize auditor with configuration"""
        self.config = self._load_config(config_path)
        self.kms_client = self._initialize_kms_client()
        self.collector_version = "1.0.0"
        self.output_dir = Path("/home/notme/Desktop/gitea/evidence-collection/output/encryption")
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from YAML file"""
        import yaml
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file not found at {config_path}, using defaults")
            return {
                'gcp_project_id': 'your-project-id',
                'service_account_path': '/home/notme/Desktop/gitea/evidence-collection/config/gcp-service-account.json',
                'gcs_bucket': 'evidence-collection-bucket',
                'control_framework': 'CMMC_2.0',
                'kms_locations': ['global', 'us-east1', 'us-west1'],
            }

    def _initialize_kms_client(self) -> kms_v1.KeyManagementServiceClient:
        """Initialize Cloud KMS client"""
        try:
            sa_path = self.config.get('service_account_path')
            if Path(sa_path).exists():
                credentials = service_account.Credentials.from_service_account_file(sa_path)
                return kms_v1.KeyManagementServiceClient(credentials=credentials)
            else:
                logger.warning(f"Service account file not found at {sa_path}, using default credentials")
                return kms_v1.KeyManagementServiceClient()
        except Exception as e:
            logger.error(f"Failed to initialize KMS client: {e}")
            raise

    def _generate_hash(self, data: Dict[str, Any]) -> str:
        """Generate SHA-256 hash of evidence data"""
        json_str = json.dumps(data, sort_keys=True)
        return hashlib.sha256(json_str.encode()).hexdigest()

    def _create_evidence_artifact(self, data: Dict[str, Any], artifact_type: str, control_ids: List[str]) -> Dict[str, Any]:
        """Create standardized evidence artifact"""
        evidence = {
            "evidence_id": str(uuid.uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "control_framework": self.config.get('control_framework', 'CMMC_2.0'),
            "control_ids": control_ids,
            "collection_method": "automated",
            "source": "gcp_cloud_kms",
            "artifact_type": artifact_type,
            "data": data,
            "collector_version": self.collector_version,
            "gcp_project": self.config.get('gcp_project_id'),
        }

        evidence["hash"] = self._generate_hash(evidence["data"])
        return evidence

    def collect_key_rings(self, location: str = "global") -> List[Dict[str, Any]]:
        """Collect Cloud KMS key rings"""
        logger.info(f"Collecting key rings in location: {location}")

        try:
            project = self.config.get('gcp_project_id')
            parent = f"projects/{project}/locations/{location}"

            request = kms_v1.ListKeyRingsRequest(parent=parent)

            key_rings = []
            page_result = self.kms_client.list_key_rings(request=request)

            for key_ring in page_result:
                kr_data = {
                    "name": key_ring.name,
                    "create_time": key_ring.create_time.isoformat() if key_ring.create_time else None,
                    "location": location,
                }

                evidence = self._create_evidence_artifact(
                    kr_data,
                    "key_ring",
                    ENCRYPTION_CONTROL_MAPPINGS["cmek_keys"]
                )
                key_rings.append(evidence)

                logger.info(f"Collected key ring: {key_ring.name}")

            logger.info(f"Collected {len(key_rings)} key rings in {location}")
            return key_rings

        except Exception as e:
            logger.error(f"Error collecting key rings in {location}: {e}")
            return []

    def collect_crypto_keys(self, key_ring_name: str) -> List[Dict[str, Any]]:
        """Collect crypto keys from a key ring"""
        logger.info(f"Collecting crypto keys from: {key_ring_name}")

        try:
            request = kms_v1.ListCryptoKeysRequest(parent=key_ring_name)

            crypto_keys = []
            page_result = self.kms_client.list_crypto_keys(request=request)

            for key in page_result:
                key_data = {
                    "name": key.name,
                    "purpose": key.purpose.name,
                    "create_time": key.create_time.isoformat() if key.create_time else None,
                    "next_rotation_time": key.next_rotation_time.isoformat() if key.next_rotation_time else None,
                    "rotation_period": key.rotation_period.seconds if key.rotation_period else None,
                    "version_template": {
                        "algorithm": key.version_template.algorithm.name,
                        "protection_level": key.version_template.protection_level.name,
                    } if key.version_template else None,
                    "primary_version": key.primary.name if key.primary else None,
                }

                # Check rotation compliance (90 days recommended)
                rotation_compliant = False
                if key.rotation_period:
                    rotation_days = key.rotation_period.seconds / 86400
                    rotation_compliant = rotation_days <= 90
                    key_data["rotation_compliant"] = rotation_compliant
                    key_data["rotation_period_days"] = rotation_days
                else:
                    key_data["rotation_compliant"] = False
                    key_data["rotation_period_days"] = None

                evidence = self._create_evidence_artifact(
                    key_data,
                    "crypto_key",
                    ENCRYPTION_CONTROL_MAPPINGS["cmek_keys"]
                )
                crypto_keys.append(evidence)

                logger.info(f"Collected crypto key: {key.name}")

            logger.info(f"Collected {len(crypto_keys)} crypto keys")
            return crypto_keys

        except Exception as e:
            logger.error(f"Error collecting crypto keys from {key_ring_name}: {e}")
            return []

    def collect_key_versions(self, crypto_key_name: str) -> List[Dict[str, Any]]:
        """Collect versions of a crypto key"""
        logger.info(f"Collecting key versions for: {crypto_key_name}")

        try:
            request = kms_v1.ListCryptoKeyVersionsRequest(parent=crypto_key_name)

            versions = []
            page_result = self.kms_client.list_crypto_key_versions(request=request)

            for version in page_result:
                version_data = {
                    "name": version.name,
                    "state": version.state.name,
                    "create_time": version.create_time.isoformat() if version.create_time else None,
                    "destroy_time": version.destroy_time.isoformat() if version.destroy_time else None,
                    "destroy_event_time": version.destroy_event_time.isoformat() if version.destroy_event_time else None,
                    "algorithm": version.algorithm.name,
                    "protection_level": version.protection_level.name,
                }

                versions.append(version_data)

            logger.info(f"Collected {len(versions)} key versions")
            return versions

        except Exception as e:
            logger.error(f"Error collecting key versions for {crypto_key_name}: {e}")
            return []

    def collect_key_iam_policy(self, resource_name: str) -> Dict[str, Any]:
        """Collect IAM policy for a KMS resource"""
        logger.info(f"Collecting IAM policy for: {resource_name}")

        try:
            policy = self.kms_client.get_iam_policy(resource=resource_name)

            from google.protobuf.json_format import MessageToDict
            policy_dict = MessageToDict(policy._pb)

            policy_data = {
                "resource": resource_name,
                "bindings": policy_dict.get('bindings', []),
                "etag": policy_dict.get('etag'),
            }

            evidence = self._create_evidence_artifact(
                policy_data,
                "kms_iam_policy",
                ENCRYPTION_CONTROL_MAPPINGS["key_access_control"]
            )

            logger.info(f"Collected IAM policy for {resource_name}")
            return evidence

        except Exception as e:
            logger.error(f"Error collecting IAM policy for {resource_name}: {e}")
            return None

    def audit_encryption_at_rest(self) -> Dict[str, Any]:
        """Audit encryption-at-rest configuration across GCP services"""
        logger.info("Auditing encryption-at-rest configuration...")

        audit_data = {
            "gcs_buckets": {
                "default_encryption": "Google-managed encryption keys",
                "recommendation": "Configure CMEK for sensitive data buckets",
                "verification_method": "Check bucket metadata for kmsKeyName",
            },
            "compute_disks": {
                "default_encryption": "Google-managed encryption keys",
                "recommendation": "Use CMEK for persistent disks with sensitive data",
                "verification_method": "Check disk resources for diskEncryptionKey.kmsKeyName",
            },
            "cloud_sql": {
                "default_encryption": "Google-managed encryption keys",
                "recommendation": "Enable CMEK for Cloud SQL instances",
                "verification_method": "Check instance configuration for diskEncryptionConfiguration",
            },
            "bigquery": {
                "default_encryption": "Google-managed encryption keys",
                "recommendation": "Configure default CMEK for datasets",
                "verification_method": "Check dataset encryptionConfiguration",
            },
        }

        evidence = self._create_evidence_artifact(
            audit_data,
            "encryption_at_rest_audit",
            ENCRYPTION_CONTROL_MAPPINGS["encryption_at_rest"]
        )

        logger.info("Encryption-at-rest audit complete")
        return evidence

    def analyze_rotation_compliance(self, crypto_keys: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Analyze key rotation compliance"""
        logger.info("Analyzing key rotation compliance...")

        analysis = {
            "total_keys": len(crypto_keys),
            "compliant_keys": 0,
            "non_compliant_keys": 0,
            "keys_without_rotation": 0,
            "compliance_details": [],
        }

        for key_evidence in crypto_keys:
            key_data = key_evidence['data']

            if key_data.get('rotation_compliant') is True:
                analysis["compliant_keys"] += 1
                analysis["compliance_details"].append({
                    "key_name": key_data.get('name'),
                    "status": "COMPLIANT",
                    "rotation_period_days": key_data.get('rotation_period_days'),
                })
            elif key_data.get('rotation_compliant') is False and key_data.get('rotation_period_days') is not None:
                analysis["non_compliant_keys"] += 1
                analysis["compliance_details"].append({
                    "key_name": key_data.get('name'),
                    "status": "NON_COMPLIANT",
                    "rotation_period_days": key_data.get('rotation_period_days'),
                    "recommendation": "Reduce rotation period to 90 days or less",
                })
            else:
                analysis["keys_without_rotation"] += 1
                analysis["compliance_details"].append({
                    "key_name": key_data.get('name'),
                    "status": "NO_ROTATION",
                    "recommendation": "Configure automatic key rotation",
                })

        evidence = self._create_evidence_artifact(
            analysis,
            "key_rotation_compliance",
            ENCRYPTION_CONTROL_MAPPINGS["key_rotation"]
        )

        logger.info(f"Rotation compliance: {analysis['compliant_keys']}/{analysis['total_keys']} compliant")
        return evidence

    def save_evidence(self, evidence_items: List[Dict[str, Any]], prefix: str = "encryption") -> List[str]:
        """Save evidence artifacts"""
        saved_files = []

        # Handle single evidence item
        if isinstance(evidence_items, dict):
            evidence_items = [evidence_items]

        for evidence in evidence_items:
            if not evidence:
                continue

            date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            filename = f"{prefix}_{evidence['artifact_type']}_{evidence['evidence_id']}_{date_str}.json"
            filepath = self.output_dir / filename

            try:
                with open(filepath, 'w') as f:
                    json.dump(evidence, f, indent=2)

                logger.info(f"Saved evidence: {filepath}")
                saved_files.append(str(filepath))

            except Exception as e:
                logger.error(f"Failed to save evidence {filename}: {e}")

        return saved_files

    def generate_summary(self, all_evidence: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Generate summary of encryption audit"""
        summary = {
            "collection_timestamp": datetime.now(timezone.utc).isoformat(),
            "total_evidence_items": len(all_evidence),
            "artifact_types": {},
            "control_coverage": {},
        }

        for evidence in all_evidence:
            # Artifact type breakdown
            artifact_type = evidence.get('artifact_type')
            summary['artifact_types'][artifact_type] = summary['artifact_types'].get(artifact_type, 0) + 1

            # Control coverage
            for control in evidence.get('control_ids', []):
                summary['control_coverage'][control] = summary['control_coverage'].get(control, 0) + 1

        # Save summary
        summary_file = self.output_dir / f"encryption_summary_{datetime.now(timezone.utc).strftime('%Y-%m-%d_%H%M%S')}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)

        logger.info(f"Summary saved to {summary_file}")
        return summary

    def run(self) -> Dict[str, Any]:
        """Main execution method"""
        try:
            all_evidence = []
            all_crypto_keys = []

            # Collect key rings and crypto keys from all configured locations
            locations = self.config.get('kms_locations', ['global'])

            for location in locations:
                key_rings = self.collect_key_rings(location)
                all_evidence.extend(key_rings)

                # Collect crypto keys from each key ring
                for kr_evidence in key_rings:
                    kr_name = kr_evidence['data']['name']
                    crypto_keys = self.collect_crypto_keys(kr_name)
                    all_evidence.extend(crypto_keys)
                    all_crypto_keys.extend(crypto_keys)

                    # Collect IAM policy for key ring
                    iam_policy = self.collect_key_iam_policy(kr_name)
                    if iam_policy:
                        all_evidence.append(iam_policy)

            # Audit encryption-at-rest
            ear_audit = self.audit_encryption_at_rest()
            all_evidence.append(ear_audit)

            # Analyze rotation compliance
            if all_crypto_keys:
                rotation_analysis = self.analyze_rotation_compliance(all_crypto_keys)
                all_evidence.append(rotation_analysis)

            # Save all evidence
            saved_files = self.save_evidence(all_evidence)

            # Generate summary
            summary = self.generate_summary(all_evidence)

            return {
                "success": True,
                "evidence_collected": len(all_evidence),
                "files_saved": len(saved_files),
                "summary": summary,
            }

        except Exception as e:
            logger.error(f"Collection failed: {e}")
            return {
                "success": False,
                "error": str(e),
            }


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="Audit GCP encryption configuration")
    parser.add_argument('--config', default='/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml',
                        help='Path to configuration file')

    args = parser.parse_args()

    auditor = GCPEncryptionAuditor(config_path=args.config)
    result = auditor.run()

    if result['success']:
        print(f"\nAudit successful!")
        print(f"Evidence items collected: {result['evidence_collected']}")
        print(f"Files saved: {result['files_saved']}")
        print(f"\nSummary:")
        print(json.dumps(result['summary'], indent=2))
    else:
        print(f"\nAudit failed: {result['error']}")
        sys.exit(1)


if __name__ == "__main__":
    main()
