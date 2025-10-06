#!/usr/bin/env python3
"""
GCP Security Command Center Evidence Collector
Collects security findings and maps to CMMC/NIST controls
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
    from google.cloud import securitycenter_v1
    from google.oauth2 import service_account
except ImportError:
    print("ERROR: google-cloud-securitycenter not installed. Run: pip install google-cloud-securitycenter")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/notme/Desktop/gitea/evidence-collection/logs/gcp-scc-collector.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Control mappings for Security Command Center findings
CONTROL_MAPPINGS = {
    "VULNERABILITY": ["SI.L2-3.14.1", "SI.L2-3.14.2", "SI.L2-3.14.3"],
    "MISCONFIGURATION": ["CM.L2-3.4.1", "CM.L2-3.4.2", "SC.L2-3.13.1"],
    "THREAT_DETECTION": ["SI.L2-3.14.4", "SI.L2-3.14.5", "IR.L2-3.6.1"],
    "DATA_EXPOSURE": ["SC.L2-3.13.11", "SC.L2-3.13.16", "MP.L2-3.8.3"],
    "ACCESS_CONTROL": ["AC.L2-3.1.1", "AC.L2-3.1.2", "AC.L2-3.1.3"],
    "ENCRYPTION": ["SC.L2-3.13.8", "SC.L2-3.13.11", "SC.L2-3.13.16"],
    "LOGGING_MONITORING": ["AU.L2-3.3.1", "AU.L2-3.3.2", "AU.L2-3.3.5"],
}

SEVERITY_CONTROL_MAPPING = {
    "CRITICAL": ["IR.L2-3.6.1", "SI.L2-3.14.2"],
    "HIGH": ["SI.L2-3.14.1", "CM.L2-3.4.7"],
    "MEDIUM": ["SI.L2-3.14.3", "RA.L2-3.11.2"],
    "LOW": ["SI.L2-3.14.4"],
}


class GCPSCCCollector:
    """Collect Security Command Center findings as evidence"""

    def __init__(self, config_path: str = "/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml"):
        """Initialize collector with configuration"""
        self.config = self._load_config(config_path)
        self.client = self._initialize_client()
        self.collector_version = "1.0.0"
        self.output_dir = Path("/home/notme/Desktop/gitea/evidence-collection/output/scc")
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

    def _initialize_client(self) -> securitycenter_v1.SecurityCenterClient:
        """Initialize Security Command Center client"""
        try:
            sa_path = self.config.get('service_account_path')
            if Path(sa_path).exists():
                credentials = service_account.Credentials.from_service_account_file(sa_path)
                return securitycenter_v1.SecurityCenterClient(credentials=credentials)
            else:
                logger.warning(f"Service account file not found at {sa_path}, using default credentials")
                return securitycenter_v1.SecurityCenterClient()
        except Exception as e:
            logger.error(f"Failed to initialize SCC client: {e}")
            raise

    def _generate_hash(self, data: Dict[str, Any]) -> str:
        """Generate SHA-256 hash of evidence data"""
        json_str = json.dumps(data, sort_keys=True)
        return hashlib.sha256(json_str.encode()).hexdigest()

    def _categorize_finding(self, finding: securitycenter_v1.Finding) -> str:
        """Categorize finding type for control mapping"""
        category = finding.category.upper()

        if "VULN" in category or "PATCH" in category:
            return "VULNERABILITY"
        elif "CONFIG" in category or "COMPLIANCE" in category:
            return "MISCONFIGURATION"
        elif "THREAT" in category or "MALWARE" in category:
            return "THREAT_DETECTION"
        elif "EXPOSURE" in category or "PUBLIC" in category:
            return "DATA_EXPOSURE"
        elif "ACCESS" in category or "IAM" in category or "PERMISSION" in category:
            return "ACCESS_CONTROL"
        elif "ENCRYPT" in category or "TLS" in category or "SSL" in category:
            return "ENCRYPTION"
        elif "LOG" in category or "AUDIT" in category or "MONITOR" in category:
            return "LOGGING_MONITORING"
        else:
            return "MISCONFIGURATION"

    def _map_controls(self, finding: securitycenter_v1.Finding) -> List[str]:
        """Map finding to CMMC controls"""
        controls = []

        # Category-based mapping
        category_type = self._categorize_finding(finding)
        controls.extend(CONTROL_MAPPINGS.get(category_type, []))

        # Severity-based mapping
        severity = finding.severity.name
        controls.extend(SEVERITY_CONTROL_MAPPING.get(severity, []))

        # Remove duplicates and return
        return list(set(controls))

    def _format_finding_evidence(self, finding: securitycenter_v1.Finding) -> Dict[str, Any]:
        """Format finding as evidence artifact"""
        finding_data = {
            "finding_name": finding.name,
            "category": finding.category,
            "severity": finding.severity.name,
            "state": finding.state.name,
            "resource_name": finding.resource_name,
            "event_time": finding.event_time.isoformat() if finding.event_time else None,
            "create_time": finding.create_time.isoformat() if finding.create_time else None,
            "source_properties": dict(finding.source_properties),
            "security_marks": dict(finding.security_marks.marks) if finding.security_marks else {},
            "external_uri": finding.external_uri,
            "mitigation": finding.mitigation,
            "finding_class": finding.finding_class.name if finding.finding_class else None,
        }

        controls = self._map_controls(finding)

        evidence = {
            "evidence_id": str(uuid.uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "control_framework": self.config.get('control_framework', 'CMMC_2.0'),
            "control_ids": controls,
            "collection_method": "automated",
            "source": "gcp_security_command_center",
            "artifact_type": "security_finding",
            "data": finding_data,
            "collector_version": self.collector_version,
            "gcp_project": self.config.get('gcp_project_id'),
            "gcp_organization": self.config.get('gcp_organization_id'),
        }

        # Add hash
        evidence["hash"] = self._generate_hash(evidence["data"])

        return evidence

    def collect_findings(self, filter_query: Optional[str] = None, max_findings: int = 1000) -> List[Dict[str, Any]]:
        """Collect Security Command Center findings"""
        logger.info("Starting Security Command Center evidence collection")

        try:
            org_name = self.config.get('gcp_organization_id')

            # Default filter: active findings from last 30 days
            if not filter_query:
                filter_query = 'state="ACTIVE"'

            request = securitycenter_v1.ListFindingsRequest(
                parent=f"{org_name}/sources/-",
                filter=filter_query,
                page_size=min(max_findings, 1000),
            )

            findings = []
            page_result = self.client.list_findings(request=request)

            for i, response in enumerate(page_result):
                if i >= max_findings:
                    break

                finding = response.finding
                evidence = self._format_finding_evidence(finding)
                findings.append(evidence)

                logger.info(f"Collected finding: {finding.category} - {finding.severity.name}")

            logger.info(f"Collected {len(findings)} findings")
            return findings

        except Exception as e:
            logger.error(f"Error collecting findings: {e}")
            raise

    def save_evidence(self, findings: List[Dict[str, Any]]) -> List[str]:
        """Save findings as evidence artifacts"""
        saved_files = []

        for finding in findings:
            # Create filename with date and hash
            date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            filename = f"scc_finding_{finding['evidence_id']}_{date_str}.json"
            filepath = self.output_dir / filename

            try:
                with open(filepath, 'w') as f:
                    json.dump(finding, f, indent=2)

                logger.info(f"Saved evidence: {filepath}")
                saved_files.append(str(filepath))

            except Exception as e:
                logger.error(f"Failed to save evidence {filename}: {e}")

        return saved_files

    def generate_summary(self, findings: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Generate summary statistics for collected findings"""
        summary = {
            "collection_timestamp": datetime.now(timezone.utc).isoformat(),
            "total_findings": len(findings),
            "severity_breakdown": {},
            "category_breakdown": {},
            "control_coverage": {},
            "state_breakdown": {},
        }

        for finding in findings:
            # Severity breakdown
            severity = finding['data']['severity']
            summary['severity_breakdown'][severity] = summary['severity_breakdown'].get(severity, 0) + 1

            # Category breakdown
            category = finding['data']['category']
            summary['category_breakdown'][category] = summary['category_breakdown'].get(category, 0) + 1

            # State breakdown
            state = finding['data']['state']
            summary['state_breakdown'][state] = summary['state_breakdown'].get(state, 0) + 1

            # Control coverage
            for control in finding.get('control_ids', []):
                summary['control_coverage'][control] = summary['control_coverage'].get(control, 0) + 1

        # Save summary
        summary_file = self.output_dir / f"summary_{datetime.now(timezone.utc).strftime('%Y-%m-%d_%H%M%S')}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)

        logger.info(f"Summary saved to {summary_file}")
        return summary

    def run(self, filter_query: Optional[str] = None, max_findings: int = 1000) -> Dict[str, Any]:
        """Main execution method"""
        try:
            # Collect findings
            findings = self.collect_findings(filter_query, max_findings)

            # Save evidence
            saved_files = self.save_evidence(findings)

            # Generate summary
            summary = self.generate_summary(findings)

            return {
                "success": True,
                "findings_collected": len(findings),
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

    parser = argparse.ArgumentParser(description="Collect GCP Security Command Center evidence")
    parser.add_argument('--config', default='/home/notme/Desktop/gitea/evidence-collection/config/evidence-config.yaml',
                        help='Path to configuration file')
    parser.add_argument('--filter', help='SCC filter query')
    parser.add_argument('--max-findings', type=int, default=1000, help='Maximum findings to collect')

    args = parser.parse_args()

    collector = GCPSCCCollector(config_path=args.config)
    result = collector.run(filter_query=args.filter, max_findings=args.max_findings)

    if result['success']:
        print(f"\nCollection successful!")
        print(f"Findings collected: {result['findings_collected']}")
        print(f"Files saved: {result['files_saved']}")
        print(f"\nSummary:")
        print(json.dumps(result['summary'], indent=2))
    else:
        print(f"\nCollection failed: {result['error']}")
        sys.exit(1)


if __name__ == "__main__":
    main()
