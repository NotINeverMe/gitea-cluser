#!/usr/bin/env python3
"""
Evidence Manifest Generator
Generates comprehensive manifest with SHA-256 hashing and metadata tracking
"""

import json
import hashlib
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Any, Optional
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class EvidenceManifestGenerator:
    """Generate and maintain evidence collection manifest"""

    def __init__(self, evidence_dir: str = "/home/notme/Desktop/gitea/evidence-collection/output"):
        """Initialize manifest generator"""
        self.evidence_dir = Path(evidence_dir)
        self.manifest_dir = Path("/home/notme/Desktop/gitea/evidence-collection/manifests")
        self.manifest_dir.mkdir(parents=True, exist_ok=True)

    def _calculate_file_hash(self, filepath: Path) -> str:
        """Calculate SHA-256 hash of a file"""
        sha256_hash = hashlib.sha256()

        try:
            with open(filepath, "rb") as f:
                # Read file in chunks to handle large files
                for byte_block in iter(lambda: f.read(4096), b""):
                    sha256_hash.update(byte_block)

            return sha256_hash.hexdigest()

        except Exception as e:
            logger.error(f"Error hashing file {filepath}: {e}")
            return None

    def _extract_evidence_metadata(self, filepath: Path) -> Optional[Dict[str, Any]]:
        """Extract metadata from evidence JSON file"""
        try:
            with open(filepath, 'r') as f:
                evidence = json.load(f)

            return {
                "evidence_id": evidence.get("evidence_id"),
                "control_framework": evidence.get("control_framework"),
                "control_ids": evidence.get("control_ids", []),
                "source": evidence.get("source"),
                "artifact_type": evidence.get("artifact_type"),
                "collection_timestamp": evidence.get("timestamp"),
                "gcp_project": evidence.get("gcp_project"),
            }

        except Exception as e:
            logger.error(f"Error reading evidence metadata from {filepath}: {e}")
            return None

    def _get_file_metadata(self, filepath: Path) -> Dict[str, Any]:
        """Get file system metadata"""
        stat = filepath.stat()

        return {
            "file_path": str(filepath),
            "file_name": filepath.name,
            "file_size_bytes": stat.st_size,
            "created_time": datetime.fromtimestamp(stat.st_ctime, tz=timezone.utc).isoformat(),
            "modified_time": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        }

    def scan_evidence_files(self, subdirectory: Optional[str] = None) -> List[Dict[str, Any]]:
        """Scan directory for evidence files and collect metadata"""
        logger.info(f"Scanning evidence directory: {self.evidence_dir}")

        if subdirectory:
            scan_dir = self.evidence_dir / subdirectory
        else:
            scan_dir = self.evidence_dir

        if not scan_dir.exists():
            logger.warning(f"Directory does not exist: {scan_dir}")
            return []

        evidence_files = []

        # Find all JSON files (evidence artifacts)
        for json_file in scan_dir.rglob("*.json"):
            # Skip summary files
            if "summary" in json_file.name.lower():
                continue

            logger.info(f"Processing: {json_file}")

            # Get file hash
            file_hash = self._calculate_file_hash(json_file)

            # Get file metadata
            file_metadata = self._get_file_metadata(json_file)

            # Extract evidence metadata
            evidence_metadata = self._extract_evidence_metadata(json_file)

            # Combine all metadata
            file_entry = {
                **file_metadata,
                "sha256_hash": file_hash,
                "evidence_metadata": evidence_metadata,
            }

            evidence_files.append(file_entry)

        logger.info(f"Scanned {len(evidence_files)} evidence files")
        return evidence_files

    def generate_manifest(self, subdirectory: Optional[str] = None) -> Dict[str, Any]:
        """Generate comprehensive evidence manifest"""
        logger.info("Generating evidence manifest...")

        evidence_files = self.scan_evidence_files(subdirectory)

        # Build manifest
        manifest = {
            "manifest_version": "1.0",
            "generated_timestamp": datetime.now(timezone.utc).isoformat(),
            "evidence_directory": str(self.evidence_dir),
            "total_files": len(evidence_files),
            "files": evidence_files,
            "statistics": self._calculate_statistics(evidence_files),
        }

        # Calculate manifest hash
        manifest_content = json.dumps(manifest, sort_keys=True, indent=2)
        manifest["manifest_hash"] = hashlib.sha256(manifest_content.encode()).hexdigest()

        logger.info("Manifest generation complete")
        return manifest

    def _calculate_statistics(self, evidence_files: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate statistics from evidence files"""
        stats = {
            "total_files": len(evidence_files),
            "total_size_bytes": 0,
            "sources": {},
            "artifact_types": {},
            "control_frameworks": {},
            "control_coverage": {},
            "gcp_projects": set(),
        }

        for file_entry in evidence_files:
            stats["total_size_bytes"] += file_entry.get("file_size_bytes", 0)

            evidence_meta = file_entry.get("evidence_metadata")
            if evidence_meta:
                # Source breakdown
                source = evidence_meta.get("source", "unknown")
                stats["sources"][source] = stats["sources"].get(source, 0) + 1

                # Artifact type breakdown
                artifact_type = evidence_meta.get("artifact_type", "unknown")
                stats["artifact_types"][artifact_type] = stats["artifact_types"].get(artifact_type, 0) + 1

                # Control framework breakdown
                framework = evidence_meta.get("control_framework", "unknown")
                stats["control_frameworks"][framework] = stats["control_frameworks"].get(framework, 0) + 1

                # Control coverage
                for control in evidence_meta.get("control_ids", []):
                    stats["control_coverage"][control] = stats["control_coverage"].get(control, 0) + 1

                # GCP projects
                project = evidence_meta.get("gcp_project")
                if project:
                    stats["gcp_projects"].add(project)

        # Convert set to list for JSON serialization
        stats["gcp_projects"] = list(stats["gcp_projects"])

        return stats

    def save_manifest(self, manifest: Dict[str, Any], filename: Optional[str] = None) -> str:
        """Save manifest to file"""
        if not filename:
            timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H%M%S")
            filename = f"evidence_manifest_{timestamp}.json"

        filepath = self.manifest_dir / filename

        try:
            with open(filepath, 'w') as f:
                json.dump(manifest, f, indent=2)

            logger.info(f"Manifest saved to {filepath}")

            # Also save hash file
            hash_file = filepath.with_suffix('.json.sha256')
            with open(hash_file, 'w') as f:
                f.write(manifest.get("manifest_hash", ""))

            return str(filepath)

        except Exception as e:
            logger.error(f"Error saving manifest: {e}")
            raise

    def verify_evidence_integrity(self, manifest_file: str) -> Dict[str, Any]:
        """Verify integrity of evidence files using manifest"""
        logger.info(f"Verifying evidence integrity using manifest: {manifest_file}")

        with open(manifest_file, 'r') as f:
            manifest = json.load(f)

        verification_results = {
            "verification_timestamp": datetime.now(timezone.utc).isoformat(),
            "manifest_file": manifest_file,
            "total_files": len(manifest.get("files", [])),
            "verified_files": 0,
            "failed_files": 0,
            "missing_files": 0,
            "failures": [],
        }

        for file_entry in manifest.get("files", []):
            filepath = Path(file_entry["file_path"])
            expected_hash = file_entry["sha256_hash"]

            if not filepath.exists():
                verification_results["missing_files"] += 1
                verification_results["failures"].append({
                    "file": str(filepath),
                    "reason": "File not found",
                })
                continue

            # Recalculate hash
            actual_hash = self._calculate_file_hash(filepath)

            if actual_hash == expected_hash:
                verification_results["verified_files"] += 1
            else:
                verification_results["failed_files"] += 1
                verification_results["failures"].append({
                    "file": str(filepath),
                    "reason": "Hash mismatch",
                    "expected_hash": expected_hash,
                    "actual_hash": actual_hash,
                })

        logger.info(f"Verification complete: {verification_results['verified_files']} verified, "
                    f"{verification_results['failed_files']} failed, "
                    f"{verification_results['missing_files']} missing")

        return verification_results

    def generate_control_mapping_report(self, manifest: Dict[str, Any]) -> Dict[str, Any]:
        """Generate control mapping report from manifest"""
        logger.info("Generating control mapping report...")

        control_report = {
            "report_timestamp": datetime.now(timezone.utc).isoformat(),
            "control_framework": "CMMC_2.0",
            "controls": {},
        }

        for file_entry in manifest.get("files", []):
            evidence_meta = file_entry.get("evidence_metadata")
            if evidence_meta:
                for control_id in evidence_meta.get("control_ids", []):
                    if control_id not in control_report["controls"]:
                        control_report["controls"][control_id] = {
                            "evidence_count": 0,
                            "sources": set(),
                            "artifact_types": set(),
                            "evidence_files": [],
                        }

                    control_report["controls"][control_id]["evidence_count"] += 1
                    control_report["controls"][control_id]["sources"].add(evidence_meta.get("source"))
                    control_report["controls"][control_id]["artifact_types"].add(evidence_meta.get("artifact_type"))
                    control_report["controls"][control_id]["evidence_files"].append(file_entry["file_name"])

        # Convert sets to lists for JSON serialization
        for control_id in control_report["controls"]:
            control_report["controls"][control_id]["sources"] = list(control_report["controls"][control_id]["sources"])
            control_report["controls"][control_id]["artifact_types"] = list(control_report["controls"][control_id]["artifact_types"])

        logger.info(f"Control mapping report generated for {len(control_report['controls'])} controls")
        return control_report

    def run(self, subdirectory: Optional[str] = None, verify: Optional[str] = None) -> Dict[str, Any]:
        """Main execution method"""
        try:
            if verify:
                # Verify existing manifest
                verification_results = self.verify_evidence_integrity(verify)
                return {
                    "success": True,
                    "operation": "verify",
                    "results": verification_results,
                }
            else:
                # Generate new manifest
                manifest = self.generate_manifest(subdirectory)
                manifest_file = self.save_manifest(manifest)

                # Generate control mapping report
                control_report = self.generate_control_mapping_report(manifest)
                report_file = self.manifest_dir / f"control_mapping_report_{datetime.now(timezone.utc).strftime('%Y-%m-%d_%H%M%S')}.json"
                with open(report_file, 'w') as f:
                    json.dump(control_report, f, indent=2)

                return {
                    "success": True,
                    "operation": "generate",
                    "manifest_file": manifest_file,
                    "control_report_file": str(report_file),
                    "statistics": manifest["statistics"],
                }

        except Exception as e:
            logger.error(f"Operation failed: {e}")
            return {
                "success": False,
                "error": str(e),
            }


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="Generate evidence collection manifest")
    parser.add_argument('--evidence-dir', default='/home/notme/Desktop/gitea/evidence-collection/output',
                        help='Path to evidence directory')
    parser.add_argument('--subdirectory', help='Specific subdirectory to scan')
    parser.add_argument('--verify', help='Verify integrity using existing manifest file')

    args = parser.parse_args()

    generator = EvidenceManifestGenerator(evidence_dir=args.evidence_dir)
    result = generator.run(subdirectory=args.subdirectory, verify=args.verify)

    if result['success']:
        if result['operation'] == 'generate':
            print(f"\nManifest generation successful!")
            print(f"Manifest file: {result['manifest_file']}")
            print(f"Control report: {result['control_report_file']}")
            print(f"\nStatistics:")
            print(json.dumps(result['statistics'], indent=2))
        else:
            print(f"\nVerification complete!")
            print(json.dumps(result['results'], indent=2))
    else:
        print(f"\nOperation failed: {result['error']}")
        sys.exit(1)


if __name__ == "__main__":
    main()
