#!/usr/bin/env python3
"""
GCP IAM & Access Control Evidence Collector
Collects user/service account inventory, role bindings, MFA status, and permissions
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
    from google.cloud import iam_admin_v1
    from google.cloud import resourcemanager_v3
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
except ImportError:
    print("ERROR: Required packages not installed. Run: pip install google-cloud-iam google-cloud-resource-manager google-api-python-client")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/notme/Desktop/gitea/evidence-collection/logs/gcp-iam-evidence.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# IAM control mappings
IAM_CONTROL_MAPPINGS = {
    "service_accounts": ["IA.L2-3.5.1", "IA.L2-3.5.2", "AC.L2-3.1.5"],
    "user_accounts": ["IA.L2-3.5.1", "IA.L2-3.5.3", "AC.L2-3.1.1"],
    "role_bindings": ["AC.L2-3.1.1", "AC.L2-3.1.2", "AC.L2-3.1.3"],
    "custom_roles": ["AC.L2-3.1.2", "AC.L2-3.1.4"],
    "mfa_enforcement": ["IA.L2-3.5.3", "IA.L2-3.5.4"],
    "key_rotation": ["IA.L2-3.5.7", "SC.L2-3.13.10"],
}


class GCPIAMEvidenceCollector:
    """Collect GCP IAM configuration as compliance evidence"""

    def __init__(self, config_path: str = "/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml"):
        """Initialize collector with configuration"""
        self.config = self._load_config(config_path)
        self.iam_client = self._initialize_iam_client()
        self.rm_client = self._initialize_rm_client()
        self.collector_version = "1.0.0"
        self.output_dir = Path("/home/notme/Desktop/gitea/evidence-collection/output/iam")
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
                'gcp_organization_id': 'organizations/your-org-id',
                'service_account_path': '/home/notme/Desktop/gitea/evidence-collection/config/gcp-service-account.json',
                'gcs_bucket': 'evidence-collection-bucket',
                'control_framework': 'CMMC_2.0',
            }

    def _initialize_iam_client(self) -> iam_admin_v1.IAMClient:
        """Initialize IAM Admin client"""
        try:
            sa_path = self.config.get('service_account_path')
            if Path(sa_path).exists():
                credentials = service_account.Credentials.from_service_account_file(sa_path)
                return iam_admin_v1.IAMClient(credentials=credentials)
            else:
                logger.warning(f"Service account file not found at {sa_path}, using default credentials")
                return iam_admin_v1.IAMClient()
        except Exception as e:
            logger.error(f"Failed to initialize IAM client: {e}")
            raise

    def _initialize_rm_client(self) -> resourcemanager_v3.ProjectsClient:
        """Initialize Resource Manager client"""
        try:
            sa_path = self.config.get('service_account_path')
            if Path(sa_path).exists():
                credentials = service_account.Credentials.from_service_account_file(sa_path)
                return resourcemanager_v3.ProjectsClient(credentials=credentials)
            else:
                return resourcemanager_v3.ProjectsClient()
        except Exception as e:
            logger.error(f"Failed to initialize Resource Manager client: {e}")
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
            "source": "gcp_iam",
            "artifact_type": artifact_type,
            "data": data,
            "collector_version": self.collector_version,
            "gcp_project": self.config.get('gcp_project_id'),
        }

        evidence["hash"] = self._generate_hash(evidence["data"])
        return evidence

    def collect_service_accounts(self) -> List[Dict[str, Any]]:
        """Collect all service accounts and their configurations"""
        logger.info("Collecting service accounts...")

        try:
            project = f"projects/{self.config.get('gcp_project_id')}"
            request = iam_admin_v1.ListServiceAccountsRequest(name=project)

            service_accounts = []
            page_result = self.iam_client.list_service_accounts(request=request)

            for sa in page_result:
                sa_data = {
                    "name": sa.name,
                    "email": sa.email,
                    "display_name": sa.display_name,
                    "description": sa.description,
                    "disabled": sa.disabled,
                    "oauth2_client_id": sa.oauth2_client_id,
                }

                # Get service account keys
                keys_request = iam_admin_v1.ListServiceAccountKeysRequest(
                    name=sa.name,
                    key_types=[iam_admin_v1.ListServiceAccountKeysRequest.KeyType.USER_MANAGED]
                )
                keys = self.iam_client.list_service_account_keys(request=keys_request)

                sa_data["user_managed_keys"] = []
                for key in keys.keys:
                    key_data = {
                        "name": key.name,
                        "key_type": key.key_type.name,
                        "key_algorithm": key.key_algorithm.name,
                        "valid_after_time": key.valid_after_time.isoformat() if key.valid_after_time else None,
                        "valid_before_time": key.valid_before_time.isoformat() if key.valid_before_time else None,
                    }
                    sa_data["user_managed_keys"].append(key_data)

                    # Check key age for rotation compliance
                    if key.valid_after_time:
                        key_age = datetime.now(timezone.utc) - key.valid_after_time
                        sa_data["key_rotation_needed"] = key_age > timedelta(days=90)

                evidence = self._create_evidence_artifact(
                    sa_data,
                    "service_account",
                    IAM_CONTROL_MAPPINGS["service_accounts"]
                )
                service_accounts.append(evidence)

                logger.info(f"Collected service account: {sa.email}")

            logger.info(f"Collected {len(service_accounts)} service accounts")
            return service_accounts

        except Exception as e:
            logger.error(f"Error collecting service accounts: {e}")
            raise

    def collect_iam_policy(self) -> Dict[str, Any]:
        """Collect IAM policy for the project"""
        logger.info("Collecting IAM policy...")

        try:
            project_name = f"projects/{self.config.get('gcp_project_id')}"

            # Get IAM policy
            project = self.rm_client.get_project(name=project_name)
            policy = self.rm_client.get_iam_policy(resource=project_name)

            from google.protobuf.json_format import MessageToDict
            policy_dict = MessageToDict(policy._pb)

            policy_data = {
                "project": project_name,
                "bindings": policy_dict.get('bindings', []),
                "etag": policy_dict.get('etag'),
                "version": policy_dict.get('version'),
            }

            # Analyze bindings
            policy_data["analysis"] = {
                "total_bindings": len(policy_dict.get('bindings', [])),
                "roles_used": list(set([b.get('role') for b in policy_dict.get('bindings', [])])),
                "members_count": {},
            }

            for binding in policy_dict.get('bindings', []):
                role = binding.get('role')
                members = binding.get('members', [])
                policy_data["analysis"]["members_count"][role] = len(members)

            evidence = self._create_evidence_artifact(
                policy_data,
                "iam_policy",
                IAM_CONTROL_MAPPINGS["role_bindings"]
            )

            logger.info("Collected IAM policy")
            return evidence

        except Exception as e:
            logger.error(f"Error collecting IAM policy: {e}")
            raise

    def collect_custom_roles(self) -> List[Dict[str, Any]]:
        """Collect custom IAM roles"""
        logger.info("Collecting custom roles...")

        try:
            project = f"projects/{self.config.get('gcp_project_id')}"
            request = iam_admin_v1.ListRolesRequest(
                parent=project,
                show_deleted=False
            )

            custom_roles = []
            page_result = self.iam_client.list_roles(request=request)

            for role in page_result:
                role_data = {
                    "name": role.name,
                    "title": role.title,
                    "description": role.description,
                    "included_permissions": list(role.included_permissions),
                    "stage": role.stage.name,
                    "deleted": role.deleted,
                }

                evidence = self._create_evidence_artifact(
                    role_data,
                    "custom_role",
                    IAM_CONTROL_MAPPINGS["custom_roles"]
                )
                custom_roles.append(evidence)

                logger.info(f"Collected custom role: {role.title}")

            logger.info(f"Collected {len(custom_roles)} custom roles")
            return custom_roles

        except Exception as e:
            logger.error(f"Error collecting custom roles: {e}")
            raise

    def collect_mfa_status(self) -> Dict[str, Any]:
        """Collect MFA enforcement status (requires Cloud Identity API)"""
        logger.info("Collecting MFA enforcement status...")

        # Note: This requires Cloud Identity API and appropriate permissions
        # For now, we'll create a placeholder evidence artifact
        mfa_data = {
            "note": "MFA status requires Cloud Identity API access",
            "recommendation": "Configure 2-Step Verification in Cloud Identity",
            "control_requirement": "Multi-factor authentication required for all user accounts",
            "verification_method": "Manual verification via Cloud Identity console",
            "verification_url": "https://admin.google.com/ac/security/2sv",
        }

        evidence = self._create_evidence_artifact(
            mfa_data,
            "mfa_enforcement",
            IAM_CONTROL_MAPPINGS["mfa_enforcement"]
        )

        logger.info("MFA status evidence created (manual verification required)")
        return evidence

    def analyze_service_account_keys(self, service_accounts: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Analyze service account key rotation compliance"""
        logger.info("Analyzing service account key rotation...")

        analysis = {
            "total_service_accounts": len(service_accounts),
            "accounts_with_keys": 0,
            "total_user_managed_keys": 0,
            "keys_needing_rotation": 0,
            "compliant_accounts": [],
            "non_compliant_accounts": [],
        }

        for sa_evidence in service_accounts:
            sa_data = sa_evidence['data']
            user_keys = sa_data.get('user_managed_keys', [])

            if user_keys:
                analysis["accounts_with_keys"] += 1
                analysis["total_user_managed_keys"] += len(user_keys)

                if sa_data.get('key_rotation_needed', False):
                    analysis["keys_needing_rotation"] += 1
                    analysis["non_compliant_accounts"].append({
                        "email": sa_data.get('email'),
                        "key_count": len(user_keys)
                    })
                else:
                    analysis["compliant_accounts"].append(sa_data.get('email'))

        evidence = self._create_evidence_artifact(
            analysis,
            "key_rotation_analysis",
            IAM_CONTROL_MAPPINGS["key_rotation"]
        )

        logger.info(f"Key rotation analysis complete: {analysis['keys_needing_rotation']} keys need rotation")
        return evidence

    def save_evidence(self, evidence_items: List[Dict[str, Any]], prefix: str = "iam") -> List[str]:
        """Save evidence artifacts"""
        saved_files = []

        # Handle single evidence item
        if isinstance(evidence_items, dict):
            evidence_items = [evidence_items]

        for evidence in evidence_items:
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
        """Generate summary of IAM evidence collection"""
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
        summary_file = self.output_dir / f"iam_summary_{datetime.now(timezone.utc).strftime('%Y-%m-%d_%H%M%S')}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)

        logger.info(f"Summary saved to {summary_file}")
        return summary

    def run(self) -> Dict[str, Any]:
        """Main execution method"""
        try:
            all_evidence = []

            # Collect service accounts
            service_accounts = self.collect_service_accounts()
            all_evidence.extend(service_accounts)

            # Collect IAM policy
            iam_policy = self.collect_iam_policy()
            all_evidence.append(iam_policy)

            # Collect custom roles
            custom_roles = self.collect_custom_roles()
            all_evidence.extend(custom_roles)

            # Collect MFA status
            mfa_status = self.collect_mfa_status()
            all_evidence.append(mfa_status)

            # Analyze key rotation
            key_analysis = self.analyze_service_account_keys(service_accounts)
            all_evidence.append(key_analysis)

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

    parser = argparse.ArgumentParser(description="Collect GCP IAM evidence")
    parser.add_argument('--config', default='/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml',
                        help='Path to configuration file')

    args = parser.parse_args()

    collector = GCPIAMEvidenceCollector(config_path=args.config)
    result = collector.run()

    if result['success']:
        print(f"\nCollection successful!")
        print(f"Evidence items collected: {result['evidence_collected']}")
        print(f"Files saved: {result['files_saved']}")
        print(f"\nSummary:")
        print(json.dumps(result['summary'], indent=2))
    else:
        print(f"\nCollection failed: {result['error']}")
        sys.exit(1)


if __name__ == "__main__":
    main()
