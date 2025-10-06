#!/usr/bin/env python3
"""
SonarQube Metrics Exporter for Prometheus
CMMC 2.0: CA.L2-3.12.3 - Security Assessment
NIST SP 800-171: 3.12.3 - Security Assessment
"""

import os
import sys
import time
import logging
import requests
from typing import Dict, List, Any
from prometheus_client import start_http_server, Gauge, Counter, Histogram, CollectorRegistry
from requests.auth import HTTPBasicAuth
import json
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
SONARQUBE_URL = os.getenv('SONARQUBE_URL', 'http://sonarqube:9000')
SONARQUBE_TOKEN = os.getenv('SONARQUBE_TOKEN', '')
PORT = int(os.getenv('PORT', 9200))
SCRAPE_INTERVAL = int(os.getenv('SCRAPE_INTERVAL', 60))

# Create custom registry
registry = CollectorRegistry()

# Define metrics with CMMC/NIST compliance labels
metrics = {
    # Quality metrics
    'bugs': Gauge('sonarqube_bugs_total', 'Total number of bugs',
                  ['project', 'branch', 'severity'], registry=registry),
    'vulnerabilities': Gauge('sonarqube_vulnerabilities_total', 'Total number of vulnerabilities',
                            ['project', 'branch', 'severity'], registry=registry),
    'code_smells': Gauge('sonarqube_code_smells_total', 'Total number of code smells',
                        ['project', 'branch', 'severity'], registry=registry),
    'security_hotspots': Gauge('sonarqube_security_hotspots', 'Number of security hotspots',
                              ['project', 'branch', 'status'], registry=registry),

    # Coverage metrics
    'coverage': Gauge('sonarqube_coverage_percent', 'Code coverage percentage',
                     ['project', 'branch'], registry=registry),
    'line_coverage': Gauge('sonarqube_line_coverage_percent', 'Line coverage percentage',
                          ['project', 'branch'], registry=registry),
    'branch_coverage': Gauge('sonarqube_branch_coverage_percent', 'Branch coverage percentage',
                            ['project', 'branch'], registry=registry),

    # Complexity metrics
    'complexity': Gauge('sonarqube_complexity', 'Cyclomatic complexity',
                       ['project', 'branch'], registry=registry),
    'cognitive_complexity': Gauge('sonarqube_cognitive_complexity', 'Cognitive complexity',
                                 ['project', 'branch'], registry=registry),

    # Duplication metrics
    'duplicated_lines': Gauge('sonarqube_duplicated_lines_percent', 'Duplicated lines percentage',
                             ['project', 'branch'], registry=registry),
    'duplicated_blocks': Gauge('sonarqube_duplicated_blocks', 'Number of duplicated blocks',
                              ['project', 'branch'], registry=registry),

    # Technical debt
    'technical_debt': Gauge('sonarqube_technical_debt_minutes', 'Technical debt in minutes',
                           ['project', 'branch'], registry=registry),
    'sqale_rating': Gauge('sonarqube_sqale_rating', 'Maintainability rating (1=A to 5=E)',
                         ['project', 'branch'], registry=registry),

    # Security metrics
    'security_rating': Gauge('sonarqube_security_rating', 'Security rating (1=A to 5=E)',
                           ['project', 'branch'], registry=registry),
    'reliability_rating': Gauge('sonarqube_reliability_rating', 'Reliability rating (1=A to 5=E)',
                              ['project', 'branch'], registry=registry),

    # Quality gate
    'quality_gate_status': Gauge('sonarqube_quality_gate_status', 'Quality gate status (1=passed, 0=failed)',
                                ['project', 'branch'], registry=registry),
    'quality_gate_details': Gauge('sonarqube_quality_gate_condition', 'Quality gate condition status',
                                 ['project', 'branch', 'metric', 'operator'], registry=registry),

    # Compliance metrics
    'cmmc_compliance_score': Gauge('sonarqube_cmmc_compliance_score', 'CMMC compliance score',
                                  ['project', 'level'], registry=registry),
    'nist_compliance_score': Gauge('sonarqube_nist_compliance_score', 'NIST compliance score',
                                  ['project', 'framework'], registry=registry),

    # Export metadata
    'last_analysis': Gauge('sonarqube_last_analysis_timestamp', 'Timestamp of last analysis',
                          ['project', 'branch'], registry=registry),
    'export_duration': Histogram('sonarqube_export_duration_seconds', 'Duration of metrics export',
                                registry=registry),
    'export_errors': Counter('sonarqube_export_errors_total', 'Total number of export errors',
                           ['error_type'], registry=registry),
}


class SonarQubeExporter:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'Accept': 'application/json',
        })
        if SONARQUBE_TOKEN:
            self.session.auth = HTTPBasicAuth(SONARQUBE_TOKEN, '')

    def get_projects(self) -> List[Dict[str, Any]]:
        """Fetch all projects from SonarQube"""
        try:
            response = self.session.get(f"{SONARQUBE_URL}/api/projects/search")
            response.raise_for_status()
            return response.json().get('components', [])
        except Exception as e:
            logger.error(f"Failed to fetch projects: {e}")
            metrics['export_errors'].labels(error_type='project_fetch').inc()
            return []

    def get_project_metrics(self, project_key: str) -> Dict[str, Any]:
        """Fetch metrics for a specific project"""
        metric_keys = [
            'bugs', 'vulnerabilities', 'code_smells', 'security_hotspots',
            'coverage', 'line_coverage', 'branch_coverage',
            'complexity', 'cognitive_complexity',
            'duplicated_lines_density', 'duplicated_blocks',
            'sqale_index', 'sqale_rating',
            'security_rating', 'reliability_rating',
            'alert_status', 'quality_gate_details',
            'last_commit_date'
        ]

        try:
            response = self.session.get(
                f"{SONARQUBE_URL}/api/measures/component",
                params={
                    'component': project_key,
                    'metricKeys': ','.join(metric_keys)
                }
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Failed to fetch metrics for {project_key}: {e}")
            metrics['export_errors'].labels(error_type='metrics_fetch').inc()
            return {}

    def get_issues_breakdown(self, project_key: str) -> Dict[str, int]:
        """Get issue breakdown by severity"""
        severities = ['BLOCKER', 'CRITICAL', 'MAJOR', 'MINOR', 'INFO']
        breakdown = {}

        for severity in severities:
            try:
                response = self.session.get(
                    f"{SONARQUBE_URL}/api/issues/search",
                    params={
                        'componentKeys': project_key,
                        'severities': severity,
                        'resolved': 'false',
                        'ps': 1  # Page size 1, we only need the count
                    }
                )
                response.raise_for_status()
                breakdown[severity] = response.json().get('total', 0)
            except Exception as e:
                logger.error(f"Failed to fetch {severity} issues for {project_key}: {e}")
                breakdown[severity] = 0

        return breakdown

    def get_security_hotspots_breakdown(self, project_key: str) -> Dict[str, int]:
        """Get security hotspots breakdown by status"""
        statuses = ['TO_REVIEW', 'REVIEWED']
        breakdown = {}

        try:
            response = self.session.get(
                f"{SONARQUBE_URL}/api/hotspots/search",
                params={
                    'projectKey': project_key,
                    'ps': 1
                }
            )
            response.raise_for_status()
            data = response.json()

            # Parse hotspot counts by status
            for status in statuses:
                breakdown[status] = sum(
                    1 for h in data.get('hotspots', [])
                    if h.get('status') == status
                )
        except Exception as e:
            logger.error(f"Failed to fetch security hotspots for {project_key}: {e}")
            for status in statuses:
                breakdown[status] = 0

        return breakdown

    def parse_metric_value(self, measure: Dict[str, Any]) -> float:
        """Parse metric value from SonarQube response"""
        value = measure.get('value', '0')

        # Handle different value types
        if measure.get('metric') == 'alert_status':
            return 1.0 if value == 'OK' else 0.0
        elif measure.get('metric') == 'sqale_index':
            # Technical debt in minutes
            try:
                return float(value)
            except:
                return 0.0
        else:
            try:
                return float(value)
            except:
                return 0.0

    def update_metrics(self):
        """Update all Prometheus metrics from SonarQube"""
        start_time = time.time()

        try:
            projects = self.get_projects()
            logger.info(f"Found {len(projects)} projects to export")

            for project in projects:
                project_key = project['key']
                project_name = project.get('name', project_key)

                # Get project metrics
                project_data = self.get_project_metrics(project_key)

                if not project_data:
                    continue

                measures = project_data.get('component', {}).get('measures', [])
                measure_dict = {m['metric']: m for m in measures}

                # Default branch (main/master)
                branch = 'main'

                # Update basic metrics
                if 'bugs' in measure_dict:
                    # Get breakdown by severity
                    issues = self.get_issues_breakdown(project_key)
                    for severity, count in issues.items():
                        if severity in ['BLOCKER', 'CRITICAL']:
                            metrics['bugs'].labels(
                                project=project_name, branch=branch, severity=severity.lower()
                            ).set(count)

                if 'vulnerabilities' in measure_dict:
                    value = self.parse_metric_value(measure_dict['vulnerabilities'])
                    metrics['vulnerabilities'].labels(
                        project=project_name, branch=branch, severity='all'
                    ).set(value)

                if 'code_smells' in measure_dict:
                    value = self.parse_metric_value(measure_dict['code_smells'])
                    metrics['code_smells'].labels(
                        project=project_name, branch=branch, severity='all'
                    ).set(value)

                # Security hotspots
                hotspots = self.get_security_hotspots_breakdown(project_key)
                for status, count in hotspots.items():
                    metrics['security_hotspots'].labels(
                        project=project_name, branch=branch, status=status.lower()
                    ).set(count)

                # Coverage metrics
                for coverage_type in ['coverage', 'line_coverage', 'branch_coverage']:
                    if coverage_type in measure_dict:
                        value = self.parse_metric_value(measure_dict[coverage_type])
                        metrics[coverage_type].labels(
                            project=project_name, branch=branch
                        ).set(value)

                # Complexity metrics
                if 'complexity' in measure_dict:
                    value = self.parse_metric_value(measure_dict['complexity'])
                    metrics['complexity'].labels(
                        project=project_name, branch=branch
                    ).set(value)

                if 'cognitive_complexity' in measure_dict:
                    value = self.parse_metric_value(measure_dict['cognitive_complexity'])
                    metrics['cognitive_complexity'].labels(
                        project=project_name, branch=branch
                    ).set(value)

                # Duplication metrics
                if 'duplicated_lines_density' in measure_dict:
                    value = self.parse_metric_value(measure_dict['duplicated_lines_density'])
                    metrics['duplicated_lines'].labels(
                        project=project_name, branch=branch
                    ).set(value)

                if 'duplicated_blocks' in measure_dict:
                    value = self.parse_metric_value(measure_dict['duplicated_blocks'])
                    metrics['duplicated_blocks'].labels(
                        project=project_name, branch=branch
                    ).set(value)

                # Technical debt
                if 'sqale_index' in measure_dict:
                    value = self.parse_metric_value(measure_dict['sqale_index'])
                    metrics['technical_debt'].labels(
                        project=project_name, branch=branch
                    ).set(value)

                # Ratings
                for rating in ['sqale_rating', 'security_rating', 'reliability_rating']:
                    if rating in measure_dict:
                        value = self.parse_metric_value(measure_dict[rating])
                        metrics[rating].labels(
                            project=project_name, branch=branch
                        ).set(value)

                # Quality gate status
                if 'alert_status' in measure_dict:
                    value = self.parse_metric_value(measure_dict['alert_status'])
                    metrics['quality_gate_status'].labels(
                        project=project_name, branch=branch
                    ).set(value)

                # Set last analysis timestamp
                metrics['last_analysis'].labels(
                    project=project_name, branch=branch
                ).set(time.time())

                # Calculate compliance scores (example logic)
                security_score = 100
                if 'security_rating' in measure_dict:
                    rating = self.parse_metric_value(measure_dict['security_rating'])
                    security_score = max(0, 100 - (rating - 1) * 25)

                metrics['cmmc_compliance_score'].labels(
                    project=project_name, level='2'
                ).set(security_score)

                metrics['nist_compliance_score'].labels(
                    project=project_name, framework='800-171'
                ).set(security_score)

            # Record export duration
            duration = time.time() - start_time
            metrics['export_duration'].observe(duration)
            logger.info(f"Metrics export completed in {duration:.2f} seconds")

        except Exception as e:
            logger.error(f"Failed to update metrics: {e}")
            metrics['export_errors'].labels(error_type='update_metrics').inc()


def main():
    """Main execution function"""
    logger.info(f"Starting SonarQube exporter on port {PORT}")
    logger.info(f"Connecting to SonarQube at {SONARQUBE_URL}")

    # Start HTTP server for Prometheus
    start_http_server(PORT, registry=registry)

    # Create exporter instance
    exporter = SonarQubeExporter()

    # Main loop
    while True:
        try:
            exporter.update_metrics()
        except Exception as e:
            logger.error(f"Unexpected error in main loop: {e}")
            metrics['export_errors'].labels(error_type='main_loop').inc()

        time.sleep(SCRAPE_INTERVAL)


if __name__ == '__main__':
    main()