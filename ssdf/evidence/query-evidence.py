#!/usr/bin/env python3
"""
SSDF Evidence Query Tool

Query and search compliance evidence from PostgreSQL database and GCS storage.
Generate compliance reports and evidence summaries.
"""

import json
import psycopg2
import psycopg2.extras
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional, Tuple
from pathlib import Path
import os
import argparse
import sys
from google.cloud import storage


class EvidenceQuery:
    """Query evidence from database and storage"""

    def __init__(self, config_path: str = None):
        """
        Initialize query tool

        Args:
            config_path: Path to configuration file
        """
        self.config = self._load_config(config_path)
        self.db_conn = None
        self.storage_client = None

    def _load_config(self, config_path: str) -> Dict:
        """Load configuration"""
        default_config = {
            "database": {
                "host": os.getenv("POSTGRES_HOST", "localhost"),
                "port": int(os.getenv("POSTGRES_PORT", "5432")),
                "database": os.getenv("POSTGRES_DB", "compliance"),
                "user": os.getenv("POSTGRES_USER", "postgres"),
                "password": os.getenv("POSTGRES_PASSWORD", "")
            },
            "gcs": {
                "bucket": os.getenv("GCS_EVIDENCE_BUCKET", "compliance-evidence-ssdf"),
                "project": os.getenv("GCP_PROJECT", ""),
                "credentials_path": os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")
            }
        }

        if config_path and os.path.exists(config_path):
            with open(config_path, 'r') as f:
                custom_config = json.load(f)
                default_config.update(custom_config)

        return default_config

    def connect_db(self):
        """Connect to PostgreSQL database"""
        if not self.db_conn or self.db_conn.closed:
            self.db_conn = psycopg2.connect(
                host=self.config['database']['host'],
                port=self.config['database']['port'],
                database=self.config['database']['database'],
                user=self.config['database']['user'],
                password=self.config['database']['password']
            )

    def connect_gcs(self):
        """Connect to GCS"""
        if not self.storage_client:
            credentials_path = self.config['gcs']['credentials_path']
            if credentials_path and os.path.exists(credentials_path):
                os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = credentials_path
            self.storage_client = storage.Client(project=self.config['gcs']['project'])

    def query_by_date_range(
        self,
        start_date: str,
        end_date: str,
        repository: str = None
    ) -> List[Dict]:
        """
        Query evidence by date range

        Args:
            start_date: Start date (ISO format)
            end_date: End date (ISO format)
            repository: Optional repository filter

        Returns:
            List of evidence records
        """
        self.connect_db()
        cursor = self.db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        query = """
        SELECT
            id,
            repository,
            commit_sha,
            workflow_id,
            practices_covered,
            evidence_path,
            evidence_hash,
            collected_at,
            tools_used
        FROM evidence_registry
        WHERE collected_at BETWEEN %s AND %s
        """

        params = [start_date, end_date]

        if repository:
            query += " AND repository = %s"
            params.append(repository)

        query += " ORDER BY collected_at DESC"

        cursor.execute(query, params)
        results = cursor.fetchall()
        cursor.close()

        return [dict(row) for row in results]

    def query_by_repository(self, repository: str, limit: int = 100) -> List[Dict]:
        """
        Query evidence by repository

        Args:
            repository: Repository name
            limit: Maximum number of results

        Returns:
            List of evidence records
        """
        self.connect_db()
        cursor = self.db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        query = """
        SELECT
            id,
            repository,
            commit_sha,
            workflow_id,
            practices_covered,
            evidence_path,
            evidence_hash,
            collected_at,
            tools_used
        FROM evidence_registry
        WHERE repository = %s
        ORDER BY collected_at DESC
        LIMIT %s
        """

        cursor.execute(query, (repository, limit))
        results = cursor.fetchall()
        cursor.close()

        return [dict(row) for row in results]

    def query_by_practice(self, practice: str, limit: int = 100) -> List[Dict]:
        """
        Query evidence by SSDF practice

        Args:
            practice: SSDF practice ID (e.g., "PW.9.1")
            limit: Maximum number of results

        Returns:
            List of evidence records
        """
        self.connect_db()
        cursor = self.db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        query = """
        SELECT
            id,
            repository,
            commit_sha,
            workflow_id,
            practices_covered,
            evidence_path,
            evidence_hash,
            collected_at,
            tools_used
        FROM evidence_registry
        WHERE %s = ANY(practices_covered)
        ORDER BY collected_at DESC
        LIMIT %s
        """

        cursor.execute(query, (practice, limit))
        results = cursor.fetchall()
        cursor.close()

        return [dict(row) for row in results]

    def query_by_tool(self, tool: str, limit: int = 100) -> List[Dict]:
        """
        Query evidence by tool

        Args:
            tool: Tool name (e.g., "Trivy", "SonarQube")
            limit: Maximum number of results

        Returns:
            List of evidence records
        """
        self.connect_db()
        cursor = self.db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        query = """
        SELECT
            id,
            repository,
            commit_sha,
            workflow_id,
            practices_covered,
            evidence_path,
            evidence_hash,
            collected_at,
            tools_used
        FROM evidence_registry
        WHERE tools_used::text LIKE %s
        ORDER BY collected_at DESC
        LIMIT %s
        """

        cursor.execute(query, (f'%{tool}%', limit))
        results = cursor.fetchall()
        cursor.close()

        return [dict(row) for row in results]

    def query_by_commit(self, commit_sha: str) -> Optional[Dict]:
        """
        Query evidence by commit SHA

        Args:
            commit_sha: Git commit SHA

        Returns:
            Evidence record or None
        """
        self.connect_db()
        cursor = self.db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        query = """
        SELECT
            id,
            repository,
            commit_sha,
            workflow_id,
            practices_covered,
            evidence_path,
            evidence_hash,
            collected_at,
            tools_used
        FROM evidence_registry
        WHERE commit_sha = %s
        """

        cursor.execute(query, (commit_sha,))
        result = cursor.fetchone()
        cursor.close()

        return dict(result) if result else None

    def get_coverage_statistics(
        self,
        repository: str = None,
        start_date: str = None,
        end_date: str = None
    ) -> Dict:
        """
        Get SSDF coverage statistics

        Args:
            repository: Optional repository filter
            start_date: Optional start date
            end_date: Optional end date

        Returns:
            Coverage statistics
        """
        self.connect_db()
        cursor = self.db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Base query
        query = """
        SELECT
            COUNT(*) as total_builds,
            COUNT(DISTINCT repository) as total_repositories,
            AVG(array_length(practices_covered, 1)) as avg_practices,
            json_agg(DISTINCT practices_covered) as all_practices
        FROM evidence_registry
        WHERE 1=1
        """

        params = []

        if repository:
            query += " AND repository = %s"
            params.append(repository)

        if start_date:
            query += " AND collected_at >= %s"
            params.append(start_date)

        if end_date:
            query += " AND collected_at <= %s"
            params.append(end_date)

        cursor.execute(query, params)
        result = cursor.fetchone()

        # Get practice frequency
        cursor.execute("""
        SELECT
            unnest(practices_covered) as practice,
            COUNT(*) as frequency
        FROM evidence_registry
        GROUP BY practice
        ORDER BY frequency DESC
        """)

        practice_freq = {row['practice']: row['frequency'] for row in cursor.fetchall()}

        cursor.close()

        return {
            'total_builds': result['total_builds'] or 0,
            'total_repositories': result['total_repositories'] or 0,
            'avg_practices_per_build': round(result['avg_practices'] or 0, 2),
            'practice_frequency': practice_freq
        }

    def list_gcs_evidence(
        self,
        repository: str = None,
        max_results: int = 100
    ) -> List[Dict]:
        """
        List evidence packages in GCS

        Args:
            repository: Optional repository filter
            max_results: Maximum results to return

        Returns:
            List of GCS blob metadata
        """
        self.connect_gcs()
        bucket = self.storage_client.bucket(self.config['gcs']['bucket'])

        prefix = f"{repository}/" if repository else ""
        blobs = bucket.list_blobs(prefix=prefix, max_results=max_results)

        results = []
        for blob in blobs:
            results.append({
                'name': blob.name,
                'size': blob.size,
                'created': blob.time_created.isoformat() if blob.time_created else None,
                'updated': blob.updated.isoformat() if blob.updated else None,
                'storage_class': blob.storage_class,
                'md5_hash': blob.md5_hash,
                'metadata': blob.metadata or {}
            })

        return results

    def generate_compliance_report(
        self,
        repository: str = None,
        start_date: str = None,
        end_date: str = None,
        output_format: str = "text"
    ) -> str:
        """
        Generate compliance report

        Args:
            repository: Optional repository filter
            start_date: Optional start date
            end_date: Optional end date
            output_format: Output format (text, json, markdown)

        Returns:
            Report string
        """
        # Get statistics
        stats = self.get_coverage_statistics(repository, start_date, end_date)

        # Get recent evidence
        if start_date and end_date:
            evidence = self.query_by_date_range(start_date, end_date, repository)
        elif repository:
            evidence = self.query_by_repository(repository, limit=50)
        else:
            evidence = []

        if output_format == "json":
            return json.dumps({
                'statistics': stats,
                'evidence_count': len(evidence),
                'evidence_records': evidence
            }, indent=2, default=str)

        elif output_format == "markdown":
            return self._generate_markdown_report(stats, evidence, repository, start_date, end_date)

        else:  # text
            return self._generate_text_report(stats, evidence, repository, start_date, end_date)

    def _generate_text_report(
        self,
        stats: Dict,
        evidence: List[Dict],
        repository: str,
        start_date: str,
        end_date: str
    ) -> str:
        """Generate text format report"""
        lines = []
        lines.append("=" * 80)
        lines.append("SSDF COMPLIANCE REPORT")
        lines.append("=" * 80)
        lines.append(f"Generated: {datetime.now(timezone.utc).isoformat()}")
        if repository:
            lines.append(f"Repository: {repository}")
        if start_date and end_date:
            lines.append(f"Date Range: {start_date} to {end_date}")
        lines.append("")

        # Statistics
        lines.append("-" * 80)
        lines.append("STATISTICS")
        lines.append("-" * 80)
        lines.append(f"Total Builds:       {stats['total_builds']}")
        lines.append(f"Total Repositories: {stats['total_repositories']}")
        lines.append(f"Avg Practices:      {stats['avg_practices_per_build']}")
        lines.append("")

        # Practice frequency
        lines.append("-" * 80)
        lines.append("PRACTICE FREQUENCY (Top 10)")
        lines.append("-" * 80)
        practice_freq = sorted(
            stats['practice_frequency'].items(),
            key=lambda x: x[1],
            reverse=True
        )[:10]

        for practice, freq in practice_freq:
            lines.append(f"{practice:10} {freq:5} occurrences")
        lines.append("")

        # Recent evidence
        if evidence:
            lines.append("-" * 80)
            lines.append(f"RECENT EVIDENCE ({len(evidence)} builds)")
            lines.append("-" * 80)
            for record in evidence[:10]:
                lines.append(f"Build ID: {record['id']}")
                lines.append(f"  Repository: {record['repository']}")
                lines.append(f"  Commit:     {record['commit_sha'][:8]}")
                lines.append(f"  Collected:  {record['collected_at']}")
                lines.append(f"  Practices:  {len(record['practices_covered'])}")
                lines.append("")

        lines.append("=" * 80)
        return "\n".join(lines)

    def _generate_markdown_report(
        self,
        stats: Dict,
        evidence: List[Dict],
        repository: str,
        start_date: str,
        end_date: str
    ) -> str:
        """Generate Markdown format report"""
        lines = []
        lines.append("# SSDF Compliance Report\n")
        lines.append(f"**Generated:** {datetime.now(timezone.utc).isoformat()}\n")
        if repository:
            lines.append(f"**Repository:** {repository}\n")
        if start_date and end_date:
            lines.append(f"**Date Range:** {start_date} to {end_date}\n")
        lines.append("")

        # Statistics
        lines.append("## Statistics\n")
        lines.append(f"- **Total Builds:** {stats['total_builds']}")
        lines.append(f"- **Total Repositories:** {stats['total_repositories']}")
        lines.append(f"- **Average Practices per Build:** {stats['avg_practices_per_build']}\n")

        # Practice frequency
        lines.append("## Practice Frequency\n")
        lines.append("| Practice | Frequency |")
        lines.append("|----------|-----------|")

        practice_freq = sorted(
            stats['practice_frequency'].items(),
            key=lambda x: x[1],
            reverse=True
        )[:10]

        for practice, freq in practice_freq:
            lines.append(f"| {practice} | {freq} |")
        lines.append("")

        # Recent evidence
        if evidence:
            lines.append(f"## Recent Evidence ({len(evidence)} builds)\n")
            for record in evidence[:10]:
                lines.append(f"### {record['repository']} - {record['commit_sha'][:8]}\n")
                lines.append(f"- **Build ID:** `{record['id']}`")
                lines.append(f"- **Collected:** {record['collected_at']}")
                lines.append(f"- **Practices Covered:** {len(record['practices_covered'])}")
                lines.append(f"- **Evidence Path:** `{record['evidence_path']}`\n")

        return "\n".join(lines)

    def export_to_csv(self, evidence: List[Dict], output_path: str):
        """
        Export evidence to CSV

        Args:
            evidence: List of evidence records
            output_path: Output CSV file path
        """
        import csv

        with open(output_path, 'w', newline='') as csvfile:
            fieldnames = [
                'id', 'repository', 'commit_sha', 'workflow_id',
                'practices_count', 'evidence_path', 'collected_at'
            ]
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

            writer.writeheader()
            for record in evidence:
                writer.writerow({
                    'id': record['id'],
                    'repository': record['repository'],
                    'commit_sha': record['commit_sha'],
                    'workflow_id': record['workflow_id'],
                    'practices_count': len(record.get('practices_covered', [])),
                    'evidence_path': record['evidence_path'],
                    'collected_at': record['collected_at']
                })

    def close(self):
        """Close database connection"""
        if self.db_conn:
            self.db_conn.close()


def main():
    """CLI entry point"""
    parser = argparse.ArgumentParser(
        description='Query SSDF compliance evidence',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Query by date range
  python query-evidence.py --start 2025-01-01 --end 2025-12-31

  # Query by repository
  python query-evidence.py --repo my-app

  # Query by SSDF practice
  python query-evidence.py --practice PW.9.1

  # Query by tool
  python query-evidence.py --tool Trivy

  # Generate compliance report
  python query-evidence.py --report --output compliance-report.txt

  # Export to CSV
  python query-evidence.py --repo my-app --csv evidence.csv

  # List GCS evidence
  python query-evidence.py --list-gcs --repo my-app
        """
    )

    # Query options
    parser.add_argument('--start', help='Start date (ISO format: YYYY-MM-DD)')
    parser.add_argument('--end', help='End date (ISO format: YYYY-MM-DD)')
    parser.add_argument('--repo', '--repository', dest='repo', help='Repository name')
    parser.add_argument('--practice', help='SSDF practice ID (e.g., PW.9.1)')
    parser.add_argument('--tool', help='Tool name (e.g., Trivy, SonarQube)')
    parser.add_argument('--commit', help='Git commit SHA')
    parser.add_argument('--limit', type=int, default=100, help='Maximum results')

    # Output options
    parser.add_argument('--report', action='store_true', help='Generate compliance report')
    parser.add_argument('--format', choices=['text', 'json', 'markdown'], default='text',
                       help='Report format')
    parser.add_argument('--output', help='Output file path')
    parser.add_argument('--csv', help='Export to CSV file')
    parser.add_argument('--list-gcs', action='store_true', help='List evidence in GCS')

    # Config
    parser.add_argument('--config', help='Configuration file path')

    args = parser.parse_args()

    query = EvidenceQuery(config_path=args.config)

    try:
        results = []

        # Query operations
        if args.commit:
            result = query.query_by_commit(args.commit)
            if result:
                results = [result]
                print(json.dumps(result, indent=2, default=str))
            else:
                print(f"No evidence found for commit: {args.commit}")

        elif args.start and args.end:
            results = query.query_by_date_range(args.start, args.end, args.repo)
            print(f"Found {len(results)} evidence records")
            for r in results:
                print(f"  {r['id']} - {r['repository']} - {r['collected_at']}")

        elif args.practice:
            results = query.query_by_practice(args.practice, args.limit)
            print(f"Found {len(results)} evidence records with practice {args.practice}")
            for r in results:
                print(f"  {r['id']} - {r['repository']} - {r['collected_at']}")

        elif args.tool:
            results = query.query_by_tool(args.tool, args.limit)
            print(f"Found {len(results)} evidence records using tool {args.tool}")
            for r in results:
                print(f"  {r['id']} - {r['repository']} - {r['collected_at']}")

        elif args.repo:
            results = query.query_by_repository(args.repo, args.limit)
            print(f"Found {len(results)} evidence records for {args.repo}")
            for r in results:
                print(f"  {r['id']} - {r['commit_sha'][:8]} - {r['collected_at']}")

        elif args.list_gcs:
            gcs_results = query.list_gcs_evidence(args.repo, args.limit)
            print(f"Found {len(gcs_results)} evidence packages in GCS")
            for blob in gcs_results:
                print(f"  {blob['name']} - {blob['size']} bytes - {blob['storage_class']}")

        elif args.report:
            report = query.generate_compliance_report(
                repository=args.repo,
                start_date=args.start,
                end_date=args.end,
                output_format=args.format
            )

            if args.output:
                with open(args.output, 'w') as f:
                    f.write(report)
                print(f"Report saved to: {args.output}")
            else:
                print(report)

        else:
            # Show statistics
            stats = query.get_coverage_statistics(args.repo, args.start, args.end)
            print(json.dumps(stats, indent=2))

        # Export to CSV if requested
        if args.csv and results:
            query.export_to_csv(results, args.csv)
            print(f"Exported {len(results)} records to: {args.csv}")

    finally:
        query.close()


if __name__ == "__main__":
    main()
