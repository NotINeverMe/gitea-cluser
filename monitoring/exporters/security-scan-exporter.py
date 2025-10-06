#!/usr/bin/env python3
"""
Security Scan Metrics Exporter (Trivy/Grype)
CMMC 2.0: RA.L2-3.11.2 - Vulnerability Scanning
NIST SP 800-171: 3.11.2 - Vulnerability Scanning
NIST SP 800-53: RA-5 - Vulnerability Scanning
"""

import os
import sys
import time
import json
import hashlib
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
from prometheus_client import start_http_server, Gauge, Counter, Histogram, CollectorRegistry
import requests
import yaml

# Configure logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
TRIVY_API_URL = os.getenv('TRIVY_API_URL', 'http://trivy:8080')
GRYPE_API_URL = os.getenv('GRYPE_API_URL', 'http://grype:8080')
SCAN_RESULTS_DIR = Path(os.getenv('SCAN_RESULTS_DIR', '/app/scan-results'))
PORT = int(os.getenv('PORT', 9201))
SCAN_INTERVAL = int(os.getenv('SCAN_INTERVAL', 300))

# Create custom registry
registry = CollectorRegistry()

# Define security metrics
metrics = {
    # Vulnerability metrics
    'vulnerability_count': Gauge(
        'security_scan_vulnerability_count',
        'Number of vulnerabilities by severity',
        ['scanner', 'component', 'severity', 'type'],
        registry=registry
    ),
    'cvss_score': Gauge(
        'security_scan_cvss_score',
        'CVSS score of vulnerabilities',
        ['scanner', 'component', 'cve_id'],
        registry=registry
    ),
    'vulnerability_age': Gauge(
        'security_scan_vulnerability_age_days',
        'Age of vulnerability in days',
        ['scanner', 'component', 'cve_id', 'severity'],
        registry=registry
    ),

    # Malware detection
    'malware_detected': Gauge(
        'security_scan_malware_detected',
        'Number of malware signatures detected',
        ['scanner', 'component', 'file', 'signature'],
        registry=registry
    ),

    # Secrets detection
    'secrets_found': Gauge(
        'security_scan_secrets_found',
        'Number of secrets/credentials found',
        ['scanner', 'repository', 'type'],
        registry=registry
    ),

    # License compliance
    'license_violations': Gauge(
        'security_scan_license_violations',
        'Number of license compliance violations',
        ['scanner', 'component', 'license', 'severity'],
        registry=registry
    ),

    # Container security
    'container_critical_count': Gauge(
        'security_scan_container_critical_vulnerabilities',
        'Critical vulnerabilities in container images',
        ['image', 'tag', 'scanner'],
        registry=registry
    ),
    'container_misconfiguration': Gauge(
        'security_scan_container_misconfigurations',
        'Container misconfigurations detected',
        ['image', 'tag', 'type', 'severity'],
        registry=registry
    ),

    # CIS benchmark compliance
    'cis_compliance_score': Gauge(
        'security_scan_cis_compliance_score',
        'CIS benchmark compliance score',
        ['component', 'benchmark', 'level'],
        registry=registry
    ),
    'cis_failed_checks': Gauge(
        'security_scan_cis_failed_checks',
        'Number of failed CIS checks',
        ['component', 'benchmark', 'severity'],
        registry=registry
    ),

    # OWASP compliance
    'owasp_violations': Gauge(
        'security_scan_owasp_violations',
        'OWASP Top 10 violations detected',
        ['scanner', 'component', 'category', 'severity'],
        registry=registry
    ),

    # Supply chain security
    'dependency_vulnerabilities': Gauge(
        'security_scan_dependency_vulnerabilities',
        'Vulnerabilities in dependencies',
        ['component', 'dependency', 'severity', 'direct'],
        registry=registry
    ),
    'outdated_dependencies': Gauge(
        'security_scan_outdated_dependencies',
        'Number of outdated dependencies',
        ['component', 'severity'],
        registry=registry
    ),

    # Scan metadata
    'scan_duration': Histogram(
        'security_scan_duration_seconds',
        'Duration of security scans',
        ['scanner', 'scan_type'],
        registry=registry
    ),
    'scan_last_success': Gauge(
        'security_scan_last_success_timestamp',
        'Timestamp of last successful scan',
        ['scanner', 'component'],
        registry=registry
    ),
    'scan_failures': Counter(
        'security_scan_failures_total',
        'Total number of scan failures',
        ['scanner', 'reason'],
        registry=registry
    ),

    # Remediation metrics
    'mttr': Gauge(
        'security_scan_mttr_hours',
        'Mean time to remediation in hours',
        ['severity', 'component'],
        registry=registry
    ),
    'remediation_backlog': Gauge(
        'security_scan_remediation_backlog',
        'Number of vulnerabilities pending remediation',
        ['severity', 'age_bucket'],
        registry=registry
    ),

    # Evidence collection
    'evidence_hash': Gauge(
        'security_scan_evidence_hash',
        'SHA256 hash of scan evidence (as label)',
        ['scanner', 'component', 'hash', 'timestamp'],
        registry=registry
    ),
}


class SecurityScanExporter:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({'Accept': 'application/json'})
        self.vulnerability_db = {}  # Track vulnerabilities for MTTR calculation

    def scan_with_trivy(self, target: str, scan_type: str = 'image') -> Optional[Dict]:
        """Run Trivy scan on target"""
        start_time = time.time()

        try:
            # Trivy API endpoint varies by scan type
            endpoint = f"{TRIVY_API_URL}/scan/{scan_type}"

            response = self.session.post(
                endpoint,
                json={
                    'target': target,
                    'format': 'json',
                    'severity': 'UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL',
                    'vuln_type': 'os,library',
                    'security_checks': 'vuln,config,secret,license'
                }
            )
            response.raise_for_status()

            duration = time.time() - start_time
            metrics['scan_duration'].labels(
                scanner='trivy', scan_type=scan_type
            ).observe(duration)

            return response.json()

        except Exception as e:
            logger.error(f"Trivy scan failed for {target}: {e}")
            metrics['scan_failures'].labels(scanner='trivy', reason=str(e)[:50]).inc()
            return None

    def scan_with_grype(self, target: str) -> Optional[Dict]:
        """Run Grype scan on target"""
        start_time = time.time()

        try:
            response = self.session.post(
                f"{GRYPE_API_URL}/scan",
                json={
                    'target': target,
                    'output': 'json',
                    'scope': 'all-layers',
                    'only_fixed': False
                }
            )
            response.raise_for_status()

            duration = time.time() - start_time
            metrics['scan_duration'].labels(
                scanner='grype', scan_type='image'
            ).observe(duration)

            return response.json()

        except Exception as e:
            logger.error(f"Grype scan failed for {target}: {e}")
            metrics['scan_failures'].labels(scanner='grype', reason=str(e)[:50]).inc()
            return None

    def process_trivy_results(self, results: Dict, component: str):
        """Process Trivy scan results and update metrics"""
        if not results:
            return

        # Count vulnerabilities by severity
        severity_counts = {
            'CRITICAL': 0,
            'HIGH': 0,
            'MEDIUM': 0,
            'LOW': 0,
            'UNKNOWN': 0
        }

        # Process each result type
        for result in results.get('Results', []):
            target = result.get('Target', component)

            # Process vulnerabilities
            for vuln in result.get('Vulnerabilities', []):
                severity = vuln.get('Severity', 'UNKNOWN')
                severity_counts[severity] += 1

                # CVSS score
                cvss_score = vuln.get('CVSS', {}).get('nvd', {}).get('V3Score', 0)
                if cvss_score:
                    metrics['cvss_score'].labels(
                        scanner='trivy',
                        component=component,
                        cve_id=vuln.get('VulnerabilityID', 'unknown')
                    ).set(cvss_score)

                # Vulnerability age
                published_date = vuln.get('PublishedDate')
                if published_date:
                    try:
                        pub_date = datetime.fromisoformat(published_date.replace('Z', '+00:00'))
                        age_days = (datetime.now() - pub_date).days
                        metrics['vulnerability_age'].labels(
                            scanner='trivy',
                            component=component,
                            cve_id=vuln.get('VulnerabilityID', 'unknown'),
                            severity=severity
                        ).set(age_days)

                        # Track for MTTR
                        vuln_id = vuln.get('VulnerabilityID')
                        if vuln_id and vuln_id not in self.vulnerability_db:
                            self.vulnerability_db[vuln_id] = {
                                'discovered': datetime.now(),
                                'severity': severity,
                                'component': component
                            }
                    except:
                        pass

            # Process misconfigurations
            for misconfig in result.get('Misconfigurations', []):
                severity = misconfig.get('Severity', 'UNKNOWN')
                config_type = misconfig.get('Type', 'unknown')

                metrics['container_misconfiguration'].labels(
                    image=component,
                    tag='latest',
                    type=config_type,
                    severity=severity
                ).inc()

            # Process secrets
            for secret in result.get('Secrets', []):
                secret_type = secret.get('RuleID', 'unknown')
                metrics['secrets_found'].labels(
                    scanner='trivy',
                    repository=component,
                    type=secret_type
                ).inc()

        # Update vulnerability counts
        for severity, count in severity_counts.items():
            metrics['vulnerability_count'].labels(
                scanner='trivy',
                component=component,
                severity=severity,
                type='all'
            ).set(count)

        # Critical vulnerabilities in containers
        metrics['container_critical_count'].labels(
            image=component,
            tag='latest',
            scanner='trivy'
        ).set(severity_counts.get('CRITICAL', 0))

        # Update last success timestamp
        metrics['scan_last_success'].labels(
            scanner='trivy',
            component=component
        ).set(time.time())

        # Generate evidence hash
        self.generate_evidence_hash('trivy', component, results)

    def process_grype_results(self, results: Dict, component: str):
        """Process Grype scan results and update metrics"""
        if not results:
            return

        # Count vulnerabilities by severity
        severity_counts = {}

        for match in results.get('matches', []):
            vulnerability = match.get('vulnerability', {})
            severity = vulnerability.get('severity', 'UNKNOWN')

            severity_counts[severity] = severity_counts.get(severity, 0) + 1

            # CVSS metrics
            for cvss in vulnerability.get('cvss', []):
                score = cvss.get('metrics', {}).get('baseScore', 0)
                if score:
                    metrics['cvss_score'].labels(
                        scanner='grype',
                        component=component,
                        cve_id=vulnerability.get('id', 'unknown')
                    ).set(score)

        # Update vulnerability counts
        for severity, count in severity_counts.items():
            metrics['vulnerability_count'].labels(
                scanner='grype',
                component=component,
                severity=severity,
                type='all'
            ).set(count)

        # Update last success timestamp
        metrics['scan_last_success'].labels(
            scanner='grype',
            component=component
        ).set(time.time())

        # Generate evidence hash
        self.generate_evidence_hash('grype', component, results)

    def scan_cis_compliance(self, component: str):
        """Scan for CIS benchmark compliance"""
        try:
            # Simulate CIS compliance check (replace with actual implementation)
            compliance_score = 85  # Example score
            failed_checks = 15

            metrics['cis_compliance_score'].labels(
                component=component,
                benchmark='CIS_Docker_Benchmark',
                level='1'
            ).set(compliance_score)

            metrics['cis_failed_checks'].labels(
                component=component,
                benchmark='CIS_Docker_Benchmark',
                severity='HIGH'
            ).set(failed_checks)

        except Exception as e:
            logger.error(f"CIS compliance scan failed: {e}")

    def check_owasp_compliance(self, component: str):
        """Check for OWASP Top 10 compliance"""
        try:
            # Example OWASP categories to check
            owasp_categories = [
                'A01:2021 – Broken Access Control',
                'A02:2021 – Cryptographic Failures',
                'A03:2021 – Injection',
                'A04:2021 – Insecure Design',
                'A05:2021 – Security Misconfiguration'
            ]

            for category in owasp_categories:
                # Simulate violation detection (replace with actual implementation)
                violations = 0  # Example

                if violations > 0:
                    metrics['owasp_violations'].labels(
                        scanner='trivy',
                        component=component,
                        category=category,
                        severity='HIGH'
                    ).set(violations)

        except Exception as e:
            logger.error(f"OWASP compliance check failed: {e}")

    def calculate_remediation_metrics(self):
        """Calculate MTTR and remediation backlog"""
        try:
            now = datetime.now()
            severity_mttr = {'CRITICAL': [], 'HIGH': [], 'MEDIUM': [], 'LOW': []}
            backlog = {'0-7d': 0, '7-30d': 0, '30-90d': 0, '90d+': 0}

            for vuln_id, data in self.vulnerability_db.items():
                age = now - data['discovered']
                severity = data['severity']

                # Calculate MTTR (simplified - in production, track actual remediation)
                if severity in severity_mttr:
                    severity_mttr[severity].append(age.total_seconds() / 3600)

                # Count backlog by age
                if age.days <= 7:
                    backlog['0-7d'] += 1
                elif age.days <= 30:
                    backlog['7-30d'] += 1
                elif age.days <= 90:
                    backlog['30-90d'] += 1
                else:
                    backlog['90d+'] += 1

            # Update MTTR metrics
            for severity, times in severity_mttr.items():
                if times:
                    avg_mttr = sum(times) / len(times)
                    metrics['mttr'].labels(
                        severity=severity,
                        component='all'
                    ).set(avg_mttr)

            # Update backlog metrics
            for age_bucket, count in backlog.items():
                metrics['remediation_backlog'].labels(
                    severity='all',
                    age_bucket=age_bucket
                ).set(count)

        except Exception as e:
            logger.error(f"Failed to calculate remediation metrics: {e}")

    def generate_evidence_hash(self, scanner: str, component: str, results: Dict):
        """Generate SHA256 hash of scan results for evidence"""
        try:
            # Create evidence object
            evidence = {
                'scanner': scanner,
                'component': component,
                'timestamp': datetime.now().isoformat(),
                'results': results
            }

            # Generate hash
            evidence_json = json.dumps(evidence, sort_keys=True)
            evidence_hash = hashlib.sha256(evidence_json.encode()).hexdigest()

            # Save evidence to file
            evidence_file = SCAN_RESULTS_DIR / f"{scanner}_{component}_{int(time.time())}.json"
            evidence_file.parent.mkdir(parents=True, exist_ok=True)

            with open(evidence_file, 'w') as f:
                json.dump({
                    'evidence': evidence,
                    'hash': evidence_hash,
                    'cmmc_controls': ['RA.L2-3.11.2', 'CA.L2-3.12.3'],
                    'nist_controls': ['3.11.2', '3.12.3']
                }, f, indent=2)

            # Update metric (using hash as label for tracking)
            metrics['evidence_hash'].labels(
                scanner=scanner,
                component=component,
                hash=evidence_hash[:16],  # Use first 16 chars of hash
                timestamp=str(int(time.time()))
            ).set(1)

            logger.info(f"Evidence saved: {evidence_file}, hash: {evidence_hash[:16]}")

        except Exception as e:
            logger.error(f"Failed to generate evidence hash: {e}")

    def scan_all_components(self):
        """Scan all configured components"""
        # List of components to scan (in production, fetch from config)
        components = [
            {'name': 'gitea/gitea:latest', 'type': 'image'},
            {'name': 'sonarqube:community', 'type': 'image'},
            {'name': 'n8nio/n8n:latest', 'type': 'image'},
            {'name': 'aquasec/trivy:latest', 'type': 'image'},
            {'name': 'grafana/grafana:latest', 'type': 'image'},
            {'name': 'prom/prometheus:latest', 'type': 'image'}
        ]

        for component in components:
            logger.info(f"Scanning {component['name']}")

            # Run Trivy scan
            trivy_results = self.scan_with_trivy(component['name'], component['type'])
            if trivy_results:
                self.process_trivy_results(trivy_results, component['name'])

            # Run Grype scan
            grype_results = self.scan_with_grype(component['name'])
            if grype_results:
                self.process_grype_results(grype_results, component['name'])

            # Check CIS compliance
            self.scan_cis_compliance(component['name'])

            # Check OWASP compliance
            self.check_owasp_compliance(component['name'])

        # Calculate remediation metrics
        self.calculate_remediation_metrics()


def main():
    """Main execution function"""
    logger.info(f"Starting Security Scan Exporter on port {PORT}")
    logger.info(f"Trivy API: {TRIVY_API_URL}")
    logger.info(f"Grype API: {GRYPE_API_URL}")

    # Start HTTP server for Prometheus
    start_http_server(PORT, registry=registry)

    # Create exporter instance
    exporter = SecurityScanExporter()

    # Main loop
    while True:
        try:
            logger.info("Starting security scan cycle")
            exporter.scan_all_components()
            logger.info("Security scan cycle completed")

        except Exception as e:
            logger.error(f"Unexpected error in main loop: {e}")
            metrics['scan_failures'].labels(scanner='all', reason='main_loop').inc()

        time.sleep(SCAN_INTERVAL)


if __name__ == '__main__':
    main()