#!/usr/bin/env python3
"""
Evidence Collection Metrics Exporter
Exposes Prometheus metrics for monitoring evidence collection
"""

import json
import os
import time
from pathlib import Path
from typing import Dict, Any
from datetime import datetime, timezone

from prometheus_client import start_http_server, Gauge, Counter, Info
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Define Prometheus metrics
evidence_files_total = Gauge(
    'evidence_files_total',
    'Total number of evidence files collected',
    ['source', 'artifact_type']
)

evidence_collection_timestamp = Gauge(
    'evidence_collection_timestamp',
    'Timestamp of last evidence collection',
    ['collector']
)

evidence_collection_errors = Counter(
    'evidence_collection_errors_total',
    'Total number of collection errors',
    ['collector', 'error_type']
)

evidence_file_size_bytes = Gauge(
    'evidence_file_size_bytes',
    'Total size of evidence files in bytes',
    ['source']
)

control_coverage = Gauge(
    'control_coverage_count',
    'Number of evidence files per control',
    ['control_id', 'framework']
)

manifest_validation_status = Gauge(
    'manifest_validation_status',
    'Status of manifest validation (1=valid, 0=invalid)'
)

collection_status = Info(
    'evidence_collection',
    'Information about evidence collection system'
)


class EvidenceMetricsCollector:
    """Collect and export evidence collection metrics"""

    def __init__(
        self,
        evidence_dir: str = "/home/notme/Desktop/gitea/evidence-collection/output",
        manifest_dir: str = "/home/notme/Desktop/gitea/evidence-collection/manifests",
        log_dir: str = "/home/notme/Desktop/gitea/evidence-collection/logs",
    ):
        """Initialize metrics collector"""
        self.evidence_dir = Path(evidence_dir)
        self.manifest_dir = Path(manifest_dir)
        self.log_dir = Path(log_dir)

    def scan_evidence_files(self) -> Dict[str, Any]:
        """Scan evidence directory and collect metrics"""
        logger.info("Scanning evidence files for metrics...")

        metrics = {
            'total_files': 0,
            'total_size': 0,
            'by_source': {},
            'by_artifact_type': {},
            'by_control': {},
        }

        if not self.evidence_dir.exists():
            logger.warning(f"Evidence directory does not exist: {self.evidence_dir}")
            return metrics

        for json_file in self.evidence_dir.rglob("*.json"):
            if "summary" in json_file.name.lower():
                continue

            try:
                with open(json_file, 'r') as f:
                    evidence = json.load(f)

                metrics['total_files'] += 1
                metrics['total_size'] += json_file.stat().st_size

                # Count by source
                source = evidence.get('source', 'unknown')
                metrics['by_source'][source] = metrics['by_source'].get(source, 0) + 1

                # Count by artifact type
                artifact_type = evidence.get('artifact_type', 'unknown')
                key = f"{source}_{artifact_type}"
                metrics['by_artifact_type'][key] = metrics['by_artifact_type'].get(key, 0) + 1

                # Count by control
                framework = evidence.get('control_framework', 'unknown')
                for control_id in evidence.get('control_ids', []):
                    control_key = f"{framework}_{control_id}"
                    metrics['by_control'][control_key] = metrics['by_control'].get(control_key, 0) + 1

            except Exception as e:
                logger.error(f"Error processing {json_file}: {e}")

        return metrics

    def scan_collector_logs(self) -> Dict[str, Any]:
        """Scan collector logs for status and errors"""
        logger.info("Scanning collector logs...")

        log_metrics = {
            'last_run': {},
            'errors': {},
        }

        if not self.log_dir.exists():
            logger.warning(f"Log directory does not exist: {self.log_dir}")
            return log_metrics

        for log_file in self.log_dir.glob("*.log"):
            collector_name = log_file.stem

            try:
                # Get last modified time as proxy for last run
                last_modified = datetime.fromtimestamp(log_file.stat().st_mtime, tz=timezone.utc)
                log_metrics['last_run'][collector_name] = last_modified.timestamp()

                # Count errors in log (simple grep-like approach)
                with open(log_file, 'r') as f:
                    error_count = sum(1 for line in f if 'ERROR' in line)
                    log_metrics['errors'][collector_name] = error_count

            except Exception as e:
                logger.error(f"Error processing log {log_file}: {e}")

        return log_metrics

    def check_manifest_validity(self) -> bool:
        """Check if latest manifest is valid"""
        logger.info("Checking manifest validity...")

        if not self.manifest_dir.exists():
            logger.warning(f"Manifest directory does not exist: {self.manifest_dir}")
            return False

        # Find latest manifest
        manifests = sorted(self.manifest_dir.glob("evidence_manifest_*.json"), reverse=True)

        if not manifests:
            logger.warning("No manifests found")
            return False

        try:
            with open(manifests[0], 'r') as f:
                manifest = json.load(f)

            # Basic validation
            required_fields = ['manifest_version', 'generated_timestamp', 'files', 'manifest_hash']
            valid = all(field in manifest for field in required_fields)

            return valid

        except Exception as e:
            logger.error(f"Error validating manifest: {e}")
            return False

    def update_metrics(self):
        """Update all Prometheus metrics"""
        logger.info("Updating metrics...")

        # Scan evidence files
        evidence_metrics = self.scan_evidence_files()

        # Update file count metrics
        for source, count in evidence_metrics['by_source'].items():
            evidence_file_size_bytes.labels(source=source).set(evidence_metrics['total_size'])

        for key, count in evidence_metrics['by_artifact_type'].items():
            source, artifact_type = key.split('_', 1)
            evidence_files_total.labels(source=source, artifact_type=artifact_type).set(count)

        # Update control coverage
        for control_key, count in evidence_metrics['by_control'].items():
            framework, control_id = control_key.split('_', 1)
            control_coverage.labels(control_id=control_id, framework=framework).set(count)

        # Scan logs
        log_metrics = self.scan_collector_logs()

        for collector, timestamp in log_metrics['last_run'].items():
            evidence_collection_timestamp.labels(collector=collector).set(timestamp)

        for collector, error_count in log_metrics['errors'].items():
            if error_count > 0:
                evidence_collection_errors.labels(collector=collector, error_type='general').inc(error_count)

        # Check manifest validity
        manifest_valid = self.check_manifest_validity()
        manifest_validation_status.set(1 if manifest_valid else 0)

        # Set collection status info
        collection_status.info({
            'version': '1.0.0',
            'evidence_directory': str(self.evidence_dir),
            'total_files': str(evidence_metrics['total_files']),
            'last_update': datetime.now(timezone.utc).isoformat(),
        })

        logger.info(f"Metrics updated: {evidence_metrics['total_files']} files tracked")

    def run(self, port: int = 9090, update_interval: int = 60):
        """Run metrics exporter server"""
        logger.info(f"Starting metrics exporter on port {port}...")

        # Start Prometheus HTTP server
        start_http_server(port)

        logger.info(f"Metrics available at http://localhost:{port}/metrics")

        # Continuous update loop
        while True:
            try:
                self.update_metrics()
            except Exception as e:
                logger.error(f"Error updating metrics: {e}")

            time.sleep(update_interval)


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="Evidence collection metrics exporter")
    parser.add_argument('--port', type=int, default=9090, help='HTTP server port')
    parser.add_argument('--interval', type=int, default=60, help='Metrics update interval (seconds)')
    parser.add_argument('--evidence-dir', default='/home/notme/Desktop/gitea/evidence-collection/output',
                        help='Evidence directory')
    parser.add_argument('--manifest-dir', default='/home/notme/Desktop/gitea/evidence-collection/manifests',
                        help='Manifest directory')
    parser.add_argument('--log-dir', default='/home/notme/Desktop/gitea/evidence-collection/logs',
                        help='Log directory')

    args = parser.parse_args()

    collector = EvidenceMetricsCollector(
        evidence_dir=args.evidence_dir,
        manifest_dir=args.manifest_dir,
        log_dir=args.log_dir
    )

    collector.run(port=args.port, update_interval=args.interval)


if __name__ == "__main__":
    main()
