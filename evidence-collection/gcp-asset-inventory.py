#!/usr/bin/env python3
"""
GCP Cloud Asset Inventory Collector
Collects resource inventory snapshots for compliance evidence
"""

import json
import hashlib
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional
import logging
import sys
from pathlib import Path

try:
    from google.cloud import asset_v1
    from google.oauth2 import service_account
except ImportError:
    print("ERROR: google-cloud-asset not installed. Run: pip install google-cloud-asset")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/notme/Desktop/gitea/evidence-collection/logs/gcp-asset-inventory.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Asset type to control mappings
ASSET_CONTROL_MAPPINGS = {
    "compute.googleapis.com/Instance": ["CM.L2-3.4.1", "CM.L2-3.4.2", "SC.L2-3.13.1"],
    "storage.googleapis.com/Bucket": ["SC.L2-3.13.16", "MP.L2-3.8.3", "AU.L2-3.3.8"],
    "iam.googleapis.com/ServiceAccount": ["IA.L2-3.5.1", "IA.L2-3.5.2", "AC.L2-3.1.5"],
    "iam.googleapis.com/Role": ["AC.L2-3.1.1", "AC.L2-3.1.2", "AC.L2-3.1.3"],
    "compute.googleapis.com/Network": ["SC.L2-3.13.1", "SC.L2-3.13.5", "SC.L2-3.13.6"],
    "compute.googleapis.com/Firewall": ["SC.L2-3.13.1", "SC.L2-3.13.5", "AC.L2-3.1.13"],
    "cloudkms.googleapis.com/CryptoKey": ["SC.L2-3.13.8", "SC.L2-3.13.11", "SC.L2-3.13.16"],
    "sqladmin.googleapis.com/Instance": ["SC.L2-3.13.16", "AU.L2-3.3.1", "CM.L2-3.4.1"],
    "container.googleapis.com/Cluster": ["CM.L2-3.4.1", "SC.L2-3.13.1", "SC.L2-3.13.6"],
}


class GCPAssetInventoryCollector:
    """Collect GCP Cloud Asset Inventory for compliance evidence"""

    def __init__(self, config_path: str = "/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml"):
        """Initialize collector with configuration"""
        self.config = self._load_config(config_path)
        self.client = self._initialize_client()
        self.collector_version = "1.0.0"
        self.output_dir = Path("/home/notme/Desktop/gitea/evidence-collection/output/asset-inventory")
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

    def _initialize_client(self) -> asset_v1.AssetServiceClient:
        """Initialize Cloud Asset Inventory client"""
        try:
            sa_path = self.config.get('service_account_path')
            if Path(sa_path).exists():
                credentials = service_account.Credentials.from_service_account_file(sa_path)
                return asset_v1.AssetServiceClient(credentials=credentials)
            else:
                logger.warning(f"Service account file not found at {sa_path}, using default credentials")
                return asset_v1.AssetServiceClient()
        except Exception as e:
            logger.error(f"Failed to initialize Asset client: {e}")
            raise

    def _generate_hash(self, data: Dict[str, Any]) -> str:
        """Generate SHA-256 hash of evidence data"""
        json_str = json.dumps(data, sort_keys=True)
        return hashlib.sha256(json_str.encode()).hexdigest()

    def _map_controls(self, asset_type: str) -> List[str]:
        """Map asset type to CMMC controls"""
        return ASSET_CONTROL_MAPPINGS.get(asset_type, ["CM.L2-3.4.1"])

    def _format_asset_evidence(self, asset: asset_v1.Asset) -> Dict[str, Any]:
        """Format asset as evidence artifact"""
        from google.protobuf.json_format import MessageToDict

        asset_dict = MessageToDict(asset._pb)

        asset_data = {
            "asset_name": asset.name,
            "asset_type": asset.asset_type,
            "resource": asset_dict.get('resource', {}),
            "iam_policy": asset_dict.get('iamPolicy', {}),
            "org_policy": asset_dict.get('orgPolicy', []),
            "access_policy": asset_dict.get('accessPolicy', {}),
            "ancestors": asset.ancestors,
            "update_time": asset.update_time.isoformat() if asset.update_time else None,
        }

        controls = self._map_controls(asset.asset_type)

        evidence = {
            "evidence_id": str(uuid.uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "control_framework": self.config.get('control_framework', 'CMMC_2.0'),
            "control_ids": controls,
            "collection_method": "automated",
            "source": "gcp_cloud_asset_inventory",
            "artifact_type": "asset_configuration",
            "data": asset_data,
            "collector_version": self.collector_version,
            "gcp_project": self.config.get('gcp_project_id'),
            "gcp_organization": self.config.get('gcp_organization_id'),
        }

        # Add hash
        evidence["hash"] = self._generate_hash(evidence["data"])

        return evidence

    def collect_assets(self, asset_types: Optional[List[str]] = None, scope: str = "project") -> List[Dict[str, Any]]:
        """Collect Cloud Asset Inventory"""
        logger.info("Starting Cloud Asset Inventory collection")

        try:
            if scope == "project":
                parent = f"projects/{self.config.get('gcp_project_id')}"
            else:
                parent = self.config.get('gcp_organization_id')

            # Content type includes resource, IAM policy, and org policy
            content_type = asset_v1.ContentType.RESOURCE

            request = asset_v1.ListAssetsRequest(
                parent=parent,
                content_type=content_type,
                asset_types=asset_types,
            )

            assets = []
            page_result = self.client.list_assets(request=request)

            for asset in page_result:
                evidence = self._format_asset_evidence(asset)
                assets.append(evidence)
                logger.info(f"Collected asset: {asset.asset_type} - {asset.name}")

            logger.info(f"Collected {len(assets)} assets")
            return assets

        except Exception as e:
            logger.error(f"Error collecting assets: {e}")
            raise

    def collect_iam_policy(self, scope: str = "project") -> List[Dict[str, Any]]:
        """Collect IAM policies for all assets"""
        logger.info("Starting IAM policy collection")

        try:
            if scope == "project":
                parent = f"projects/{self.config.get('gcp_project_id')}"
            else:
                parent = self.config.get('gcp_organization_id')

            request = asset_v1.ListAssetsRequest(
                parent=parent,
                content_type=asset_v1.ContentType.IAM_POLICY,
            )

            policies = []
            page_result = self.client.list_assets(request=request)

            for asset in page_result:
                if asset.iam_policy:
                    evidence = self._format_asset_evidence(asset)
                    # Override control IDs for IAM policies
                    evidence['control_ids'] = ["AC.L2-3.1.1", "AC.L2-3.1.2", "AC.L2-3.1.3", "IA.L2-3.5.1"]
                    evidence['artifact_type'] = "iam_policy"
                    policies.append(evidence)
                    logger.info(f"Collected IAM policy: {asset.name}")

            logger.info(f"Collected {len(policies)} IAM policies")
            return policies

        except Exception as e:
            logger.error(f"Error collecting IAM policies: {e}")
            raise

    def save_evidence(self, assets: List[Dict[str, Any]], artifact_type: str = "asset") -> List[str]:
        """Save assets as evidence artifacts"""
        saved_files = []

        for asset in assets:
            # Create filename with date and hash
            date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            filename = f"{artifact_type}_{asset['evidence_id']}_{date_str}.json"
            filepath = self.output_dir / filename

            try:
                with open(filepath, 'w') as f:
                    json.dump(asset, f, indent=2)

                logger.info(f"Saved evidence: {filepath}")
                saved_files.append(str(filepath))

            except Exception as e:
                logger.error(f"Failed to save evidence {filename}: {e}")

        return saved_files

    def generate_summary(self, assets: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Generate summary statistics for collected assets"""
        summary = {
            "collection_timestamp": datetime.now(timezone.utc).isoformat(),
            "total_assets": len(assets),
            "asset_type_breakdown": {},
            "control_coverage": {},
        }

        for asset in assets:
            # Asset type breakdown
            asset_type = asset['data']['asset_type']
            summary['asset_type_breakdown'][asset_type] = summary['asset_type_breakdown'].get(asset_type, 0) + 1

            # Control coverage
            for control in asset.get('control_ids', []):
                summary['control_coverage'][control] = summary['control_coverage'].get(control, 0) + 1

        # Save summary
        summary_file = self.output_dir / f"summary_{datetime.now(timezone.utc).strftime('%Y-%m-%d_%H%M%S')}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)

        logger.info(f"Summary saved to {summary_file}")
        return summary

    def run(self, asset_types: Optional[List[str]] = None, collect_iam: bool = True, scope: str = "project") -> Dict[str, Any]:
        """Main execution method"""
        try:
            all_assets = []

            # Collect assets
            assets = self.collect_assets(asset_types, scope)
            all_assets.extend(assets)

            # Collect IAM policies
            if collect_iam:
                iam_policies = self.collect_iam_policy(scope)
                all_assets.extend(iam_policies)

            # Save evidence
            saved_files = self.save_evidence(all_assets)

            # Generate summary
            summary = self.generate_summary(all_assets)

            return {
                "success": True,
                "assets_collected": len(all_assets),
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

    parser = argparse.ArgumentParser(description="Collect GCP Cloud Asset Inventory evidence")
    parser.add_argument('--config', default='/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml',
                        help='Path to configuration file')
    parser.add_argument('--asset-types', nargs='+', help='Specific asset types to collect')
    parser.add_argument('--no-iam', action='store_true', help='Skip IAM policy collection')
    parser.add_argument('--scope', choices=['project', 'organization'], default='project',
                        help='Collection scope')

    args = parser.parse_args()

    collector = GCPAssetInventoryCollector(config_path=args.config)
    result = collector.run(
        asset_types=args.asset_types,
        collect_iam=not args.no_iam,
        scope=args.scope
    )

    if result['success']:
        print(f"\nCollection successful!")
        print(f"Assets collected: {result['assets_collected']}")
        print(f"Files saved: {result['files_saved']}")
        print(f"\nSummary:")
        print(json.dumps(result['summary'], indent=2))
    else:
        print(f"\nCollection failed: {result['error']}")
        sys.exit(1)


if __name__ == "__main__":
    main()
