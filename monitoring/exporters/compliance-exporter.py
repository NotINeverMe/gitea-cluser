#!/usr/bin/env python3
"""
Compliance Metrics Exporter for Prometheus
CMMC 2.0: CA.L2-3.12.1 - Security Assessment
NIST SP 800-171: 3.12.1 - Security Assessment
NIST SP 800-53: CA-2 - Security Assessments
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
import yaml

# Configure logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
COMPLIANCE_CONFIG = Path(os.getenv('COMPLIANCE_CONFIG', '/app/config/compliance.yml'))
EVIDENCE_PATH = Path(os.getenv('EVIDENCE_PATH', '/app/evidence'))
PORT = int(os.getenv('PORT', 9202))
SCAN_INTERVAL = int(os.getenv('SCAN_INTERVAL', 300))

# Create custom registry
registry = CollectorRegistry()

# Define compliance metrics
metrics = {
    # Control implementation metrics
    'control_implemented': Gauge(
        'compliance_control_implemented',
        'Whether control is implemented (1=yes, 0=no)',
        ['framework', 'control_id', 'description', 'required', 'level'],
        registry=registry
    ),
    'control_total': Gauge(
        'compliance_control_total',
        'Total number of controls',
        ['framework', 'required', 'level'],
        registry=registry
    ),
    'control_coverage_percent': Gauge(
        'compliance_control_coverage_percent',
        'Percentage of controls implemented',
        ['framework', 'level'],
        registry=registry
    ),

    # CMMC specific metrics
    'cmmc_control_gap': Gauge(
        'compliance_cmmc_control_gap',
        'Number of CMMC controls not implemented',
        ['level', 'domain'],
        registry=registry
    ),
    'cmmc_practice_score': Gauge(
        'compliance_cmmc_practice_score',
        'CMMC practice implementation score',
        ['domain', 'practice_id'],
        registry=registry
    ),

    # Assessment readiness
    'assessment_readiness_score': Gauge(
        'compliance_assessment_readiness_score',
        'Overall assessment readiness percentage',
        ['framework'],
        registry=registry
    ),
    'assessment_gaps': Gauge(
        'compliance_assessment_gaps',
        'Number of gaps for assessment',
        ['framework', 'severity'],
        registry=registry
    ),

    # Evidence collection
    'evidence_collection_status': Gauge(
        'compliance_evidence_collection_status',
        'Evidence collection status (1=complete, 0=incomplete)',
        ['framework', 'control_id'],
        registry=registry
    ),
    'evidence_last_updated': Gauge(
        'compliance_evidence_last_updated',
        'Timestamp of last evidence update',
        ['framework', 'control_id'],
        registry=registry
    ),
    'evidence_collection_failures': Counter(
        'compliance_evidence_collection_failures',
        'Failed evidence collection attempts',
        ['framework', 'control_id', 'reason'],
        registry=registry
    ),

    # Policy compliance
    'policy_violations': Counter(
        'compliance_policy_violations_total',
        'Total policy violations detected',
        ['policy', 'severity'],
        registry=registry
    ),
    'policy_compliance_score': Gauge(
        'compliance_policy_compliance_score',
        'Policy compliance score percentage',
        ['policy_type'],
        registry=registry
    ),

    # Vulnerability remediation compliance
    'vulnerability_age_days': Gauge(
        'compliance_vulnerability_age_days',
        'Age of unresolved vulnerabilities',
        ['severity', 'component'],
        registry=registry
    ),
    'vulnerability_sla_breach': Gauge(
        'compliance_vulnerability_sla_breach',
        'Number of vulnerabilities breaching SLA',
        ['severity'],
        registry=registry
    ),
    'vulnerability_remediated_on_time': Gauge(
        'compliance_vulnerability_remediated_on_time',
        'Vulnerabilities remediated within SLA',
        ['severity'],
        registry=registry
    ),
    'vulnerability_total': Gauge(
        'compliance_vulnerability_total',
        'Total vulnerabilities',
        ['severity'],
        registry=registry
    ),

    # Configuration compliance
    'configuration_drift_detected': Gauge(
        'compliance_configuration_drift_detected',
        'Number of configuration drifts detected',
        ['resource', 'environment'],
        registry=registry
    ),
    'configuration_baseline_compliance': Gauge(
        'compliance_configuration_baseline_compliance',
        'Baseline configuration compliance percentage',
        ['resource_type'],
        registry=registry
    ),

    # Access review compliance
    'access_review_timestamp': Gauge(
        'compliance_access_review_timestamp',
        'Last access review timestamp',
        ['system', 'review_type'],
        registry=registry
    ),
    'access_review_overdue': Gauge(
        'compliance_access_review_overdue',
        'Number of overdue access reviews',
        ['system'],
        registry=registry
    ),

    # Backup compliance
    'backup_last_successful_timestamp': Gauge(
        'backup_last_successful_timestamp',
        'Timestamp of last successful backup',
        ['system', 'backup_type'],
        registry=registry
    ),
    'backup_compliance_status': Gauge(
        'backup_compliance_status',
        'Backup compliance status (1=compliant, 0=non-compliant)',
        ['system'],
        registry=registry
    ),

    # Encryption compliance
    'unencrypted_data_detected': Gauge(
        'compliance_unencrypted_data_detected',
        'Number of unencrypted sensitive data instances',
        ['data_type', 'location'],
        registry=registry
    ),
    'encryption_compliance_score': Gauge(
        'compliance_encryption_compliance_score',
        'Encryption compliance score percentage',
        ['data_classification'],
        registry=registry
    ),

    # Audit log compliance
    'audit_log_retention_days': Gauge(
        'compliance_audit_log_retention_days',
        'Current audit log retention in days',
        ['system'],
        registry=registry
    ),
    'audit_log_gaps': Gauge(
        'compliance_audit_log_gaps',
        'Number of audit log gaps detected',
        ['system', 'time_period'],
        registry=registry
    ),

    # Scan metadata
    'scan_duration': Histogram(
        'compliance_scan_duration_seconds',
        'Duration of compliance scans',
        ['scan_type'],
        registry=registry
    ),
    'scan_failures': Counter(
        'compliance_scan_failures_total',
        'Total compliance scan failures',
        ['scan_type', 'reason'],
        registry=registry
    ),
}


class ComplianceExporter:
    def __init__(self):
        self.config = self.load_config()
        self.evidence_tracker = {}

    def load_config(self) -> Dict:
        """Load compliance configuration"""
        try:
            if COMPLIANCE_CONFIG.exists():
                with open(COMPLIANCE_CONFIG, 'r') as f:
                    return yaml.safe_load(f)
            else:
                logger.warning(f"Config file not found: {COMPLIANCE_CONFIG}")
                return self.get_default_config()
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return self.get_default_config()

    def get_default_config(self) -> Dict:
        """Return default compliance configuration"""
        return {
            'frameworks': {
                'cmmc': {
                    'level': 2,
                    'domains': [
                        'AC', 'AU', 'AT', 'CM', 'IA', 'IR', 'MA',
                        'MP', 'PE', 'PS', 'RA', 'CA', 'SC', 'SI', 'SR'
                    ],
                    'controls': self.get_cmmc_controls()
                },
                'nist_800_171': {
                    'families': [
                        '3.1', '3.2', '3.3', '3.4', '3.5', '3.6', '3.7',
                        '3.8', '3.9', '3.10', '3.11', '3.12', '3.13', '3.14'
                    ],
                    'controls': self.get_nist_controls()
                },
                'nist_800_53': {
                    'families': [
                        'AC', 'AU', 'AT', 'CM', 'CP', 'IA', 'IR', 'MA',
                        'MP', 'PE', 'PL', 'PS', 'RA', 'CA', 'SC', 'SI', 'SA'
                    ],
                    'controls': self.get_nist_53_controls()
                }
            },
            'policies': {
                'password_policy': {
                    'min_length': 14,
                    'complexity': True,
                    'max_age_days': 90
                },
                'access_review': {
                    'frequency_days': 90,
                    'privileged_frequency_days': 30
                },
                'vulnerability_remediation': {
                    'critical_sla_days': 7,
                    'high_sla_days': 30,
                    'medium_sla_days': 90,
                    'low_sla_days': 180
                },
                'backup': {
                    'frequency_hours': 24,
                    'retention_days': 90,
                    'offsite_required': True
                },
                'audit_log': {
                    'retention_days': 90,
                    'tamper_protection': True
                }
            }
        }

    def get_cmmc_controls(self) -> List[Dict]:
        """Get CMMC Level 2 controls"""
        return [
            # Access Control
            {'id': 'AC.L2-3.1.1', 'description': 'Limit system access', 'required': True},
            {'id': 'AC.L2-3.1.2', 'description': 'Limit system access to types of transactions', 'required': True},
            {'id': 'AC.L2-3.1.3', 'description': 'Control flow of CUI', 'required': True},
            {'id': 'AC.L2-3.1.4', 'description': 'Separate duties of individuals', 'required': True},
            {'id': 'AC.L2-3.1.5', 'description': 'Least privilege principle', 'required': True},

            # Audit and Accountability
            {'id': 'AU.L2-3.3.1', 'description': 'System auditing logging', 'required': True},
            {'id': 'AU.L2-3.3.2', 'description': 'User actions auditing', 'required': True},
            {'id': 'AU.L2-3.3.3', 'description': 'Review audit logs', 'required': True},
            {'id': 'AU.L2-3.3.4', 'description': 'Alert on audit failures', 'required': True},

            # Configuration Management
            {'id': 'CM.L2-3.4.1', 'description': 'Baseline configurations', 'required': True},
            {'id': 'CM.L2-3.4.2', 'description': 'Configuration change control', 'required': True},
            {'id': 'CM.L2-3.4.3', 'description': 'Security impact analysis', 'required': True},
            {'id': 'CM.L2-3.4.4', 'description': 'Access restrictions for changes', 'required': True},

            # Incident Response
            {'id': 'IR.L2-3.6.1', 'description': 'Incident handling', 'required': True},
            {'id': 'IR.L2-3.6.2', 'description': 'Incident tracking and reporting', 'required': True},
            {'id': 'IR.L2-3.6.3', 'description': 'Test incident response', 'required': True},

            # Risk Assessment
            {'id': 'RA.L2-3.11.1', 'description': 'Risk assessments', 'required': True},
            {'id': 'RA.L2-3.11.2', 'description': 'Vulnerability scanning', 'required': True},
            {'id': 'RA.L2-3.11.3', 'description': 'Remediate vulnerabilities', 'required': True},

            # Security Assessment
            {'id': 'CA.L2-3.12.1', 'description': 'Security control assessments', 'required': True},
            {'id': 'CA.L2-3.12.2', 'description': 'Plan of action', 'required': True},
            {'id': 'CA.L2-3.12.3', 'description': 'Monitor security controls', 'required': True},
            {'id': 'CA.L2-3.12.4', 'description': 'System security plans', 'required': True},

            # System and Information Integrity
            {'id': 'SI.L2-3.14.1', 'description': 'Flaw remediation', 'required': True},
            {'id': 'SI.L2-3.14.2', 'description': 'Malicious code protection', 'required': True},
            {'id': 'SI.L2-3.14.3', 'description': 'Update malicious code protection', 'required': True},
            {'id': 'SI.L2-3.14.4', 'description': 'System monitoring', 'required': True},
            {'id': 'SI.L2-3.14.5', 'description': 'Security alerts and advisories', 'required': True},
        ]

    def get_nist_controls(self) -> List[Dict]:
        """Get NIST SP 800-171 controls"""
        # Subset for demonstration - add all controls in production
        return [
            {'id': '3.1.1', 'description': 'Limit system access', 'required': True},
            {'id': '3.3.1', 'description': 'Create audit records', 'required': True},
            {'id': '3.4.1', 'description': 'Establish baseline configurations', 'required': True},
            {'id': '3.6.1', 'description': 'Establish incident response capability', 'required': True},
            {'id': '3.11.1', 'description': 'Periodically assess risk', 'required': True},
            {'id': '3.11.2', 'description': 'Scan for vulnerabilities', 'required': True},
            {'id': '3.12.1', 'description': 'Periodically assess security controls', 'required': True},
            {'id': '3.13.1', 'description': 'Monitor and control communications', 'required': True},
            {'id': '3.14.1', 'description': 'Identify and correct flaws', 'required': True},
        ]

    def get_nist_53_controls(self) -> List[Dict]:
        """Get NIST SP 800-53 controls"""
        # Subset for demonstration - add all controls in production
        return [
            {'id': 'AC-2', 'description': 'Account Management', 'required': True},
            {'id': 'AU-3', 'description': 'Content of Audit Records', 'required': True},
            {'id': 'AU-6', 'description': 'Audit Review, Analysis, and Reporting', 'required': True},
            {'id': 'CA-2', 'description': 'Security Assessments', 'required': True},
            {'id': 'CA-7', 'description': 'Continuous Monitoring', 'required': True},
            {'id': 'CM-2', 'description': 'Baseline Configuration', 'required': True},
            {'id': 'IR-4', 'description': 'Incident Handling', 'required': True},
            {'id': 'RA-5', 'description': 'Vulnerability Scanning', 'required': True},
            {'id': 'SI-2', 'description': 'Flaw Remediation', 'required': True},
            {'id': 'SI-3', 'description': 'Malicious Code Protection', 'required': True},
            {'id': 'SI-4', 'description': 'Information System Monitoring', 'required': True},
        ]

    def check_control_implementation(self):
        """Check implementation status of all controls"""
        start_time = time.time()

        try:
            for framework_name, framework_config in self.config['frameworks'].items():
                controls = framework_config.get('controls', [])
                total_controls = len(controls)
                implemented_controls = 0
                required_implemented = 0
                total_required = 0

                for control in controls:
                    control_id = control['id']
                    description = control['description']
                    required = control.get('required', False)
                    level = framework_config.get('level', 'N/A')

                    # Check if control is implemented (simplified logic)
                    is_implemented = self.check_single_control(framework_name, control_id)

                    # Update metrics
                    metrics['control_implemented'].labels(
                        framework=framework_name,
                        control_id=control_id,
                        description=description,
                        required=str(required),
                        level=str(level)
                    ).set(1 if is_implemented else 0)

                    if is_implemented:
                        implemented_controls += 1
                        if required:
                            required_implemented += 1

                    if required:
                        total_required += 1

                    # Check evidence status
                    self.check_evidence_status(framework_name, control_id)

                # Update totals
                metrics['control_total'].labels(
                    framework=framework_name,
                    required='true',
                    level=str(framework_config.get('level', 'N/A'))
                ).set(total_required)

                metrics['control_total'].labels(
                    framework=framework_name,
                    required='false',
                    level=str(framework_config.get('level', 'N/A'))
                ).set(total_controls - total_required)

                # Calculate coverage
                coverage_percent = (implemented_controls / total_controls * 100) if total_controls > 0 else 0
                metrics['control_coverage_percent'].labels(
                    framework=framework_name,
                    level=str(framework_config.get('level', 'N/A'))
                ).set(coverage_percent)

                # Assessment readiness
                readiness_score = (required_implemented / total_required * 100) if total_required > 0 else 0
                metrics['assessment_readiness_score'].labels(
                    framework=framework_name
                ).set(readiness_score)

                # CMMC specific metrics
                if framework_name == 'cmmc':
                    self.check_cmmc_gaps(framework_config, controls)

            # Record scan duration
            duration = time.time() - start_time
            metrics['scan_duration'].labels(scan_type='control_implementation').observe(duration)

        except Exception as e:
            logger.error(f"Control implementation check failed: {e}")
            metrics['scan_failures'].labels(scan_type='control_implementation', reason=str(e)[:50]).inc()

    def check_single_control(self, framework: str, control_id: str) -> bool:
        """Check if a single control is implemented"""
        # In production, this would check actual implementation
        # For demo, use evidence existence as proxy
        evidence_file = EVIDENCE_PATH / framework / f"{control_id}.json"
        return evidence_file.exists()

    def check_evidence_status(self, framework: str, control_id: str):
        """Check evidence collection status for a control"""
        try:
            evidence_file = EVIDENCE_PATH / framework / f"{control_id}.json"

            if evidence_file.exists():
                # Evidence exists
                metrics['evidence_collection_status'].labels(
                    framework=framework,
                    control_id=control_id
                ).set(1)

                # Check last update time
                mtime = evidence_file.stat().st_mtime
                metrics['evidence_last_updated'].labels(
                    framework=framework,
                    control_id=control_id
                ).set(mtime)

                # Check if evidence is stale (>30 days)
                age_days = (time.time() - mtime) / 86400
                if age_days > 30:
                    logger.warning(f"Stale evidence for {framework}/{control_id}: {age_days:.1f} days old")

            else:
                # Evidence missing
                metrics['evidence_collection_status'].labels(
                    framework=framework,
                    control_id=control_id
                ).set(0)

                metrics['evidence_collection_failures'].labels(
                    framework=framework,
                    control_id=control_id,
                    reason='missing'
                ).inc()

        except Exception as e:
            logger.error(f"Failed to check evidence for {framework}/{control_id}: {e}")
            metrics['evidence_collection_failures'].labels(
                framework=framework,
                control_id=control_id,
                reason='error'
            ).inc()

    def check_cmmc_gaps(self, framework_config: Dict, controls: List[Dict]):
        """Check CMMC specific gaps"""
        try:
            level = framework_config.get('level', 2)
            domains = framework_config.get('domains', [])

            for domain in domains:
                domain_controls = [c for c in controls if c['id'].startswith(f"{domain}.L{level}")]
                implemented = sum(1 for c in domain_controls if self.check_single_control('cmmc', c['id']))
                gaps = len(domain_controls) - implemented

                metrics['cmmc_control_gap'].labels(
                    level=str(level),
                    domain=domain
                ).set(gaps)

                # Practice score (percentage implemented)
                if domain_controls:
                    score = (implemented / len(domain_controls)) * 100
                    for control in domain_controls:
                        metrics['cmmc_practice_score'].labels(
                            domain=domain,
                            practice_id=control['id']
                        ).set(score if self.check_single_control('cmmc', control['id']) else 0)

        except Exception as e:
            logger.error(f"Failed to check CMMC gaps: {e}")

    def check_policy_compliance(self):
        """Check compliance with security policies"""
        try:
            policies = self.config.get('policies', {})

            # Password policy compliance
            if 'password_policy' in policies:
                # Simulate password policy check
                violations = 0  # In production, check actual violations
                metrics['policy_violations'].labels(
                    policy='password_policy',
                    severity='HIGH'
                ).inc(violations)

            # Vulnerability remediation SLA
            if 'vulnerability_remediation' in policies:
                sla_config = policies['vulnerability_remediation']
                self.check_vulnerability_sla(sla_config)

            # Backup compliance
            if 'backup' in policies:
                backup_config = policies['backup']
                self.check_backup_compliance(backup_config)

            # Access review compliance
            if 'access_review' in policies:
                review_config = policies['access_review']
                self.check_access_review_compliance(review_config)

        except Exception as e:
            logger.error(f"Policy compliance check failed: {e}")

    def check_vulnerability_sla(self, sla_config: Dict):
        """Check vulnerability remediation SLA compliance"""
        try:
            # Simulate vulnerability tracking (in production, integrate with vulnerability scanner)
            vulnerabilities = {
                'critical': {'total': 2, 'overdue': 0, 'on_time': 2},
                'high': {'total': 10, 'overdue': 2, 'on_time': 8},
                'medium': {'total': 25, 'overdue': 5, 'on_time': 20},
                'low': {'total': 50, 'overdue': 10, 'on_time': 40}
            }

            for severity, data in vulnerabilities.items():
                metrics['vulnerability_total'].labels(severity=severity).set(data['total'])
                metrics['vulnerability_sla_breach'].labels(severity=severity).set(data['overdue'])
                metrics['vulnerability_remediated_on_time'].labels(severity=severity).set(data['on_time'])

                # Set age for overdue vulnerabilities
                if data['overdue'] > 0:
                    sla_days = sla_config.get(f"{severity}_sla_days", 30)
                    metrics['vulnerability_age_days'].labels(
                        severity=severity,
                        component='example'
                    ).set(sla_days + 5)  # Example: 5 days overdue

        except Exception as e:
            logger.error(f"Vulnerability SLA check failed: {e}")

    def check_backup_compliance(self, backup_config: Dict):
        """Check backup compliance"""
        try:
            systems = ['gitea', 'sonarqube', 'grafana', 'prometheus']

            for system in systems:
                # Simulate backup status check
                last_backup = time.time() - (20 * 3600)  # 20 hours ago
                metrics['backup_last_successful_timestamp'].labels(
                    system=system,
                    backup_type='full'
                ).set(last_backup)

                # Check compliance
                frequency_hours = backup_config.get('frequency_hours', 24)
                is_compliant = (time.time() - last_backup) < (frequency_hours * 3600)

                metrics['backup_compliance_status'].labels(
                    system=system
                ).set(1 if is_compliant else 0)

        except Exception as e:
            logger.error(f"Backup compliance check failed: {e}")

    def check_access_review_compliance(self, review_config: Dict):
        """Check access review compliance"""
        try:
            systems = ['gitea', 'sonarqube', 'grafana', 'gcp']
            frequency_days = review_config.get('frequency_days', 90)

            for system in systems:
                # Simulate last review check
                last_review = time.time() - (85 * 86400)  # 85 days ago
                metrics['access_review_timestamp'].labels(
                    system=system,
                    review_type='standard'
                ).set(last_review)

                # Check if overdue
                days_since_review = (time.time() - last_review) / 86400
                is_overdue = days_since_review > frequency_days

                metrics['access_review_overdue'].labels(
                    system=system
                ).set(1 if is_overdue else 0)

        except Exception as e:
            logger.error(f"Access review compliance check failed: {e}")

    def check_configuration_compliance(self):
        """Check configuration compliance"""
        try:
            # Simulate configuration drift detection
            resources = ['kubernetes', 'terraform', 'docker', 'ansible']

            for resource in resources:
                # Random drift detection for demo
                drift_count = 0  # In production, check actual drift
                metrics['configuration_drift_detected'].labels(
                    resource=resource,
                    environment='production'
                ).set(drift_count)

                # Baseline compliance
                compliance_percent = 95  # In production, calculate actual compliance
                metrics['configuration_baseline_compliance'].labels(
                    resource_type=resource
                ).set(compliance_percent)

        except Exception as e:
            logger.error(f"Configuration compliance check failed: {e}")

    def check_encryption_compliance(self):
        """Check encryption compliance"""
        try:
            # Simulate encryption checks
            data_types = ['pii', 'phi', 'financial', 'credentials']

            for data_type in data_types:
                # Check for unencrypted data
                unencrypted_count = 0  # In production, scan for actual unencrypted data
                metrics['unencrypted_data_detected'].labels(
                    data_type=data_type,
                    location='database'
                ).set(unencrypted_count)

                # Encryption compliance score
                compliance_score = 100 if unencrypted_count == 0 else 80
                metrics['encryption_compliance_score'].labels(
                    data_classification=data_type
                ).set(compliance_score)

        except Exception as e:
            logger.error(f"Encryption compliance check failed: {e}")

    def run_compliance_scan(self):
        """Run complete compliance scan"""
        logger.info("Starting compliance scan")

        # Check control implementation
        self.check_control_implementation()

        # Check policy compliance
        self.check_policy_compliance()

        # Check configuration compliance
        self.check_configuration_compliance()

        # Check encryption compliance
        self.check_encryption_compliance()

        logger.info("Compliance scan completed")


def main():
    """Main execution function"""
    logger.info(f"Starting Compliance Exporter on port {PORT}")
    logger.info(f"Evidence path: {EVIDENCE_PATH}")
    logger.info(f"Config file: {COMPLIANCE_CONFIG}")

    # Create evidence directory if it doesn't exist
    EVIDENCE_PATH.mkdir(parents=True, exist_ok=True)

    # Start HTTP server for Prometheus
    start_http_server(PORT, registry=registry)

    # Create exporter instance
    exporter = ComplianceExporter()

    # Main loop
    while True:
        try:
            exporter.run_compliance_scan()
        except Exception as e:
            logger.error(f"Unexpected error in main loop: {e}")
            metrics['scan_failures'].labels(scan_type='main_loop', reason=str(e)[:50]).inc()

        time.sleep(SCAN_INTERVAL)


if __name__ == '__main__':
    main()