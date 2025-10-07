#!/usr/bin/env python3
"""
SSDF Evidence Manifest Generator

Generates structured manifest files for SSDF compliance evidence packages.
Provides detailed mapping of evidence to SSDF practices with verification metadata.
"""

import json
import hashlib
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional
from pathlib import Path
import uuid


class ManifestGenerator:
    """Generate SSDF evidence manifests"""

    def __init__(self, manifest_dir: str = "/home/notme/Desktop/gitea/ssdf/evidence/manifests"):
        """
        Initialize manifest generator

        Args:
            manifest_dir: Directory to store manifests
        """
        self.manifest_dir = Path(manifest_dir)
        self.manifest_dir.mkdir(parents=True, exist_ok=True)

        # SSDF Practice definitions
        self.ssdf_practices = self._load_ssdf_practices()

    def _load_ssdf_practices(self) -> Dict:
        """Load SSDF practice definitions"""
        return {
            # Prepare the Organization (PO)
            "PO.1.1": {
                "group": "PO",
                "title": "Identify and document all security requirements",
                "description": "Define security requirements for software development"
            },
            "PO.3.1": {
                "group": "PO",
                "title": "Implement automated build processes",
                "description": "Use automated tools for building and integrating software"
            },
            "PO.3.2": {
                "group": "PO",
                "title": "Build from version-controlled code",
                "description": "Ensure all builds use code from version control"
            },
            "PO.5.1": {
                "group": "PO",
                "title": "Implement secure coding practices",
                "description": "Follow secure coding standards and guidelines"
            },

            # Protect the Software (PS)
            "PS.1.1": {
                "group": "PS",
                "title": "Store and protect code and artifacts",
                "description": "Securely store source code and build artifacts"
            },
            "PS.2.1": {
                "group": "PS",
                "title": "Provide integrity verification mechanism",
                "description": "Sign software and provide verification methods"
            },
            "PS.3.1": {
                "group": "PS",
                "title": "Archive and protect records",
                "description": "Maintain records of software provenance and security"
            },

            # Produce Well-Secured Software (PW)
            "PW.1.1": {
                "group": "PW",
                "title": "Design software securely",
                "description": "Incorporate security into software design"
            },
            "PW.4.1": {
                "group": "PW",
                "title": "Review code for security issues",
                "description": "Perform code reviews with security focus"
            },
            "PW.4.4": {
                "group": "PW",
                "title": "Review third-party components",
                "description": "Assess security of third-party dependencies"
            },
            "PW.5.1": {
                "group": "PW",
                "title": "Test for security weaknesses",
                "description": "Conduct security testing during development"
            },
            "PW.6.1": {
                "group": "PW",
                "title": "Use automated SAST tools",
                "description": "Employ static application security testing"
            },
            "PW.6.2": {
                "group": "PW",
                "title": "Use automated DAST tools",
                "description": "Employ dynamic application security testing"
            },
            "PW.7.1": {
                "group": "PW",
                "title": "Review and address code findings",
                "description": "Triage and remediate identified vulnerabilities"
            },
            "PW.8.1": {
                "group": "PW",
                "title": "Scan for known vulnerabilities",
                "description": "Check dependencies for known security issues"
            },
            "PW.8.2": {
                "group": "PW",
                "title": "Track and remediate vulnerabilities",
                "description": "Maintain vulnerability inventory and remediation"
            },
            "PW.9.1": {
                "group": "PW",
                "title": "Generate SBOM",
                "description": "Create software bill of materials"
            },
            "PW.9.2": {
                "group": "PW",
                "title": "Distribute SBOM",
                "description": "Make SBOM available to stakeholders"
            },

            # Respond to Vulnerabilities (RV)
            "RV.1.1": {
                "group": "RV",
                "title": "Monitor for vulnerabilities",
                "description": "Continuously monitor for new threats"
            },
            "RV.1.2": {
                "group": "RV",
                "title": "Identify affected software",
                "description": "Determine scope of vulnerability impact"
            },
            "RV.2.1": {
                "group": "RV",
                "title": "Analyze vulnerabilities",
                "description": "Assess severity and impact of findings"
            },
            "RV.2.2": {
                "group": "RV",
                "title": "Prioritize remediation",
                "description": "Rank vulnerabilities for remediation"
            },
            "RV.3.1": {
                "group": "RV",
                "title": "Remediate vulnerabilities",
                "description": "Fix or mitigate identified issues"
            },
            "RV.3.3": {
                "group": "RV",
                "title": "Distribute fixed software",
                "description": "Release patched versions to users"
            }
        }

    def calculate_file_hash(self, file_path: str) -> str:
        """
        Calculate SHA-256 hash of file

        Args:
            file_path: Path to file

        Returns:
            Hash string with sha256: prefix
        """
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return f"sha256:{sha256_hash.hexdigest()}"

    def generate_manifest(
        self,
        build_id: str,
        repository: str,
        commit_sha: str,
        evidence_files: List[Dict],
        practices_covered: List[Dict],
        attestations: List[Dict] = None,
        metadata: Dict = None
    ) -> Dict:
        """
        Generate evidence manifest

        Args:
            build_id: Unique build identifier
            repository: Repository name
            commit_sha: Git commit SHA
            evidence_files: List of evidence file metadata
            practices_covered: List of SSDF practices with evidence mapping
            attestations: List of attestation metadata
            metadata: Additional metadata

        Returns:
            Manifest dictionary
        """
        if attestations is None:
            attestations = []
        if metadata is None:
            metadata = {}

        # Calculate coverage statistics
        total_practices = len(self.ssdf_practices)
        unique_practices = set(p['practice'] for p in practices_covered)
        practices_covered_count = len(unique_practices)
        coverage_percent = round((practices_covered_count / total_practices) * 100, 2)

        # Group practices by category
        practices_by_group = {}
        for practice_id in unique_practices:
            if practice_id in self.ssdf_practices:
                group = self.ssdf_practices[practice_id]['group']
                if group not in practices_by_group:
                    practices_by_group[group] = []
                practices_by_group[group].append(practice_id)

        # Build manifest
        manifest = {
            "manifest_version": "1.0",
            "schema": "https://example.com/schemas/ssdf-evidence-manifest/v1.0",
            "build_id": build_id,
            "repository": repository,
            "commit_sha": commit_sha,
            "branch": metadata.get("branch", "main"),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "collector": {
                "name": "SSDF Evidence Collector",
                "version": "1.0.0",
                "framework": "NIST SSDF 1.1"
            },

            # SSDF Practice Coverage
            "ssdf_practices_covered": [
                {
                    "practice": p['practice'],
                    "title": self.ssdf_practices.get(p['practice'], {}).get('title', 'Unknown'),
                    "group": self.ssdf_practices.get(p['practice'], {}).get('group', 'Unknown'),
                    "tool": p['tool'],
                    "evidence": p['evidence'],
                    "description": p.get('description', ''),
                    "verification_method": p.get('verification_method', ''),
                    "timestamp": p.get('timestamp', datetime.now(timezone.utc).isoformat())
                }
                for p in practices_covered
            ],

            # Evidence Files
            "evidence_files": [
                {
                    "filename": ef['filename'],
                    "hash": ef['hash'],
                    "size": ef['size'],
                    "tool": ef['tool'],
                    "format": ef['format'],
                    "collected_at": ef.get('collected_at', datetime.now(timezone.utc).isoformat()),
                    "source_url": ef.get('source_url', None),
                    "mime_type": ef.get('mime_type', 'application/octet-stream')
                }
                for ef in evidence_files
            ],

            # Attestations
            "attestations": [
                {
                    "type": a['type'],
                    "file": a['file'],
                    "signature": a.get('signature', 'none'),
                    "verified": a.get('verified', False),
                    "public_key_id": a.get('public_key_id', None),
                    "algorithm": a.get('algorithm', 'ECDSA-P256-SHA256'),
                    "timestamp": a.get('timestamp', datetime.now(timezone.utc).isoformat())
                }
                for a in attestations
            ],

            # Compliance Summary
            "compliance_summary": {
                "framework": "NIST SSDF 1.1",
                "total_practices": total_practices,
                "practices_covered": practices_covered_count,
                "coverage_percent": coverage_percent,
                "practices_by_group": {
                    group: len(practices)
                    for group, practices in practices_by_group.items()
                },
                "missing_practices": [
                    {
                        "practice": pid,
                        "title": pdata['title'],
                        "group": pdata['group']
                    }
                    for pid, pdata in self.ssdf_practices.items()
                    if pid not in unique_practices
                ]
            },

            # Tool Inventory
            "tools_used": self._generate_tool_inventory(evidence_files, practices_covered),

            # Retention and Storage
            "retention": {
                "policy": "7-year retention per compliance requirements",
                "retention_days": 2555,
                "storage_class_transitions": [
                    {
                        "days": 90,
                        "storage_class": "COLDLINE",
                        "description": "Move to cold storage after 90 days"
                    },
                    {
                        "days": 365,
                        "storage_class": "ARCHIVE",
                        "description": "Move to archive storage after 1 year"
                    }
                ],
                "deletion_date": self._calculate_deletion_date(2555)
            },

            # Additional Metadata
            "metadata": {
                "workflow_id": metadata.get("workflow_id", None),
                "run_number": metadata.get("run_number", None),
                "triggering_actor": metadata.get("actor", None),
                "build_duration": metadata.get("duration", None),
                "build_status": metadata.get("status", "success"),
                "environment": metadata.get("environment", "production"),
                "tags": metadata.get("tags", [])
            }
        }

        return manifest

    def _generate_tool_inventory(self, evidence_files: List[Dict], practices_covered: List[Dict]) -> List[Dict]:
        """Generate inventory of tools used"""
        tools = {}

        # Collect from evidence files
        for ef in evidence_files:
            tool_name = ef.get('tool', 'Unknown')
            if tool_name not in tools:
                tools[tool_name] = {
                    "name": tool_name,
                    "evidence_count": 0,
                    "practices": set(),
                    "formats": set()
                }
            tools[tool_name]["evidence_count"] += 1
            tools[tool_name]["formats"].add(ef.get('format', 'Unknown'))

        # Add practices
        for p in practices_covered:
            tool_name = p.get('tool', 'Unknown')
            if tool_name in tools:
                tools[tool_name]["practices"].add(p['practice'])

        # Convert sets to lists for JSON serialization
        return [
            {
                "name": tool_data["name"],
                "evidence_count": tool_data["evidence_count"],
                "practices_covered": sorted(list(tool_data["practices"])),
                "formats": sorted(list(tool_data["formats"]))
            }
            for tool_name, tool_data in tools.items()
        ]

    def _calculate_deletion_date(self, retention_days: int) -> str:
        """Calculate deletion date based on retention period"""
        from datetime import timedelta
        deletion_date = datetime.now(timezone.utc) + timedelta(days=retention_days)
        return deletion_date.isoformat()

    def save_manifest(self, manifest: Dict, build_id: str = None) -> str:
        """
        Save manifest to file

        Args:
            manifest: Manifest dictionary
            build_id: Optional build ID (uses manifest build_id if not provided)

        Returns:
            Path to saved manifest file
        """
        if build_id is None:
            build_id = manifest.get('build_id', str(uuid.uuid4()))

        manifest_filename = f"{build_id}.json"
        manifest_path = self.manifest_dir / manifest_filename

        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2, default=str)

        # Calculate and add manifest hash
        manifest_hash = self.calculate_file_hash(str(manifest_path))
        manifest['manifest_hash'] = manifest_hash

        # Re-save with hash
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2, default=str)

        return str(manifest_path)

    def load_manifest(self, build_id: str) -> Optional[Dict]:
        """
        Load manifest from file

        Args:
            build_id: Build identifier

        Returns:
            Manifest dictionary or None if not found
        """
        manifest_filename = f"{build_id}.json"
        manifest_path = self.manifest_dir / manifest_filename

        if not manifest_path.exists():
            return None

        with open(manifest_path, 'r') as f:
            return json.load(f)

    def verify_manifest(self, build_id: str) -> Dict:
        """
        Verify manifest integrity

        Args:
            build_id: Build identifier

        Returns:
            Verification result dictionary
        """
        manifest = self.load_manifest(build_id)

        if not manifest:
            return {
                "valid": False,
                "error": "Manifest not found"
            }

        result = {
            "valid": True,
            "errors": [],
            "warnings": []
        }

        # Check required fields
        required_fields = [
            "manifest_version", "build_id", "repository",
            "commit_sha", "timestamp", "ssdf_practices_covered",
            "evidence_files", "compliance_summary"
        ]

        for field in required_fields:
            if field not in manifest:
                result["valid"] = False
                result["errors"].append(f"Missing required field: {field}")

        # Verify hash if present
        if "manifest_hash" in manifest:
            stored_hash = manifest.pop("manifest_hash")
            manifest_path = self.manifest_dir / f"{build_id}.json"

            # Temporarily save without hash to recalculate
            temp_path = manifest_path.with_suffix('.tmp')
            with open(temp_path, 'w') as f:
                json.dump(manifest, f, indent=2, default=str)

            calculated_hash = self.calculate_file_hash(str(temp_path))
            temp_path.unlink()

            # Restore hash
            manifest["manifest_hash"] = stored_hash

            if calculated_hash != stored_hash:
                result["warnings"].append(
                    f"Hash mismatch: stored={stored_hash}, calculated={calculated_hash}"
                )

        # Check coverage
        if manifest.get("compliance_summary", {}).get("coverage_percent", 0) < 80:
            result["warnings"].append(
                f"Low SSDF coverage: {manifest['compliance_summary']['coverage_percent']}%"
            )

        return result

    def generate_summary_report(self, build_id: str) -> str:
        """
        Generate human-readable summary report

        Args:
            build_id: Build identifier

        Returns:
            Summary report as string
        """
        manifest = self.load_manifest(build_id)

        if not manifest:
            return f"Manifest not found for build: {build_id}"

        summary = []
        summary.append("=" * 80)
        summary.append("SSDF COMPLIANCE EVIDENCE MANIFEST")
        summary.append("=" * 80)
        summary.append(f"Build ID:        {manifest['build_id']}")
        summary.append(f"Repository:      {manifest['repository']}")
        summary.append(f"Commit SHA:      {manifest['commit_sha']}")
        summary.append(f"Timestamp:       {manifest['timestamp']}")
        summary.append("")

        # Compliance Summary
        cs = manifest['compliance_summary']
        summary.append("-" * 80)
        summary.append("COMPLIANCE SUMMARY")
        summary.append("-" * 80)
        summary.append(f"Framework:       {cs['framework']}")
        summary.append(f"Total Practices: {cs['total_practices']}")
        summary.append(f"Covered:         {cs['practices_covered']} ({cs['coverage_percent']}%)")
        summary.append("")

        summary.append("Practices by Group:")
        for group, count in cs.get('practices_by_group', {}).items():
            summary.append(f"  {group}: {count}")
        summary.append("")

        # Evidence Files
        summary.append("-" * 80)
        summary.append(f"EVIDENCE FILES ({len(manifest['evidence_files'])})")
        summary.append("-" * 80)
        for ef in manifest['evidence_files']:
            summary.append(f"  {ef['filename']}")
            summary.append(f"    Tool:   {ef['tool']}")
            summary.append(f"    Hash:   {ef['hash']}")
            summary.append(f"    Size:   {ef['size']} bytes")
        summary.append("")

        # Attestations
        if manifest.get('attestations'):
            summary.append("-" * 80)
            summary.append(f"ATTESTATIONS ({len(manifest['attestations'])})")
            summary.append("-" * 80)
            for att in manifest['attestations']:
                summary.append(f"  {att['type']}")
                summary.append(f"    File:     {att['file']}")
                summary.append(f"    Verified: {att['verified']}")
        summary.append("")

        # Tools Used
        summary.append("-" * 80)
        summary.append("TOOLS USED")
        summary.append("-" * 80)
        for tool in manifest.get('tools_used', []):
            summary.append(f"  {tool['name']}")
            summary.append(f"    Evidence:  {tool['evidence_count']} files")
            summary.append(f"    Practices: {len(tool['practices_covered'])}")
        summary.append("")

        summary.append("=" * 80)

        return "\n".join(summary)


def main():
    """CLI entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='SSDF Evidence Manifest Generator')
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')

    # Verify command
    verify_parser = subparsers.add_parser('verify', help='Verify manifest integrity')
    verify_parser.add_argument('build_id', help='Build ID')

    # Summary command
    summary_parser = subparsers.add_parser('summary', help='Generate summary report')
    summary_parser.add_argument('build_id', help='Build ID')

    # List command
    list_parser = subparsers.add_parser('list', help='List all manifests')

    args = parser.parse_args()

    generator = ManifestGenerator()

    if args.command == 'verify':
        result = generator.verify_manifest(args.build_id)
        print(json.dumps(result, indent=2))

    elif args.command == 'summary':
        report = generator.generate_summary_report(args.build_id)
        print(report)

    elif args.command == 'list':
        manifests = list(generator.manifest_dir.glob('*.json'))
        print(f"Found {len(manifests)} manifests:")
        for manifest_path in sorted(manifests):
            print(f"  {manifest_path.stem}")

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
