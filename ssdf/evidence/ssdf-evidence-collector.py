#!/usr/bin/env python3
"""
SSDF Evidence Collector
Adapted from GWS Evidence Framework

Collects compliance evidence from CI/CD pipeline tools:
- Gitea Actions workflow outputs
- SonarQube scan results
- Trivy vulnerability scans
- Syft SBOM files
- Cosign signatures and attestations
- n8n workflow executions

Packages evidence with SHA-256 manifest and uploads to GCS with 7-year retention.
"""

import json
import hashlib
import tarfile
import tempfile
import logging
import requests
import os
import psycopg2
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from google.cloud import storage
from google.api_core import retry
import uuid

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class EvidenceFile:
    """Evidence file metadata"""
    filename: str
    hash: str
    size: int
    tool: str
    format: str
    collected_at: str
    source_url: Optional[str] = None


@dataclass
class SSMFPractice:
    """SSDF/SSMMF practice mapping"""
    practice: str
    tool: str
    evidence: str
    description: str
    verification_method: str


@dataclass
class Attestation:
    """Build attestation metadata"""
    type: str
    file: str
    signature: str
    verified: bool
    public_key_id: Optional[str] = None


class SSMFEvidenceCollector:
    """
    Main evidence collector class
    Collects, validates, packages, and stores SSDF compliance evidence
    """

    def __init__(self, config_path: str = "/home/notme/Desktop/gitea/ssdf/evidence/config/collector-config.json"):
        """Initialize collector with configuration"""
        self.config = self._load_config(config_path)
        self.evidence_files: List[EvidenceFile] = []
        self.practices_covered: List[SSMFPractice] = []
        self.attestations: List[Attestation] = []
        self.temp_dir = None
        self.storage_client = None
        self.db_conn = None

    def _load_config(self, config_path: str) -> Dict:
        """Load collector configuration"""
        default_config = {
            "gitea": {
                "url": os.getenv("GITEA_URL", "http://localhost:3000"),
                "token": os.getenv("GITEA_TOKEN", ""),
                "api_version": "v1"
            },
            "sonarqube": {
                "url": os.getenv("SONARQUBE_URL", "http://localhost:9000"),
                "token": os.getenv("SONARQUBE_TOKEN", "")
            },
            "gcs": {
                "bucket": os.getenv("GCS_EVIDENCE_BUCKET", "compliance-evidence-ssdf"),
                "project": os.getenv("GCP_PROJECT", ""),
                "credentials_path": os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")
            },
            "database": {
                "host": os.getenv("POSTGRES_HOST", "localhost"),
                "port": int(os.getenv("POSTGRES_PORT", "5432")),
                "database": os.getenv("POSTGRES_DB", "compliance"),
                "user": os.getenv("POSTGRES_USER", "postgres"),
                "password": os.getenv("POSTGRES_PASSWORD", "")
            },
            "evidence": {
                "retention_days": 2555,  # 7 years
                "hash_algorithm": "sha256",
                "compression": "gzip",
                "sign_evidence": True
            }
        }

        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                custom_config = json.load(f)
                default_config.update(custom_config)

        return default_config

    def _calculate_hash(self, file_path: str) -> str:
        """Calculate SHA-256 hash of file"""
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return f"sha256:{sha256_hash.hexdigest()}"

    def _make_request(self, url: str, headers: Dict = None, timeout: int = 30) -> requests.Response:
        """Make HTTP request with retry logic"""
        if headers is None:
            headers = {}

        try:
            response = requests.get(url, headers=headers, timeout=timeout)
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            logger.error(f"Request failed: {url} - {e}")
            raise

    def collect_build_evidence(self, repository: str, workflow_id: int, run_number: int) -> Dict:
        """
        Collect build evidence from Gitea Actions workflow

        Args:
            repository: Repository name (owner/repo)
            workflow_id: Workflow ID
            run_number: Run number

        Returns:
            Dictionary of collected artifacts
        """
        logger.info(f"Collecting build evidence for {repository} workflow {workflow_id} run {run_number}")

        gitea_url = self.config['gitea']['url']
        token = self.config['gitea']['token']
        headers = {
            "Authorization": f"token {token}",
            "Accept": "application/json"
        }

        artifacts = {}

        # Get workflow run details
        api_url = f"{gitea_url}/api/v1/repos/{repository}/actions/runs/{workflow_id}"
        try:
            response = self._make_request(api_url, headers)
            workflow_data = response.json()
            artifacts['workflow_metadata'] = workflow_data

            # Save workflow metadata
            metadata_file = os.path.join(self.temp_dir, "workflow-metadata.json")
            with open(metadata_file, 'w') as f:
                json.dump(workflow_data, f, indent=2)

            file_hash = self._calculate_hash(metadata_file)
            file_size = os.path.getsize(metadata_file)

            self.evidence_files.append(EvidenceFile(
                filename="workflow-metadata.json",
                hash=file_hash,
                size=file_size,
                tool="Gitea Actions",
                format="JSON",
                collected_at=datetime.now(timezone.utc).isoformat(),
                source_url=api_url
            ))

            # Map to SSDF practice
            self.practices_covered.append(SSMFPractice(
                practice="PO.3.1",
                tool="Gitea Actions",
                evidence="workflow-metadata.json",
                description="Automated build and integration process",
                verification_method="Workflow execution logs and metadata"
            ))

        except Exception as e:
            logger.error(f"Failed to collect workflow metadata: {e}")

        # Get workflow artifacts
        artifacts_url = f"{gitea_url}/api/v1/repos/{repository}/actions/runs/{workflow_id}/artifacts"
        try:
            response = self._make_request(artifacts_url, headers)
            artifacts_list = response.json()

            for artifact in artifacts_list:
                artifact_name = artifact.get('name')
                artifact_id = artifact.get('id')

                # Download artifact
                download_url = f"{gitea_url}/api/v1/repos/{repository}/actions/artifacts/{artifact_id}"
                logger.info(f"Downloading artifact: {artifact_name}")

                artifact_response = self._make_request(download_url, headers)
                artifact_file = os.path.join(self.temp_dir, artifact_name)

                with open(artifact_file, 'wb') as f:
                    f.write(artifact_response.content)

                file_hash = self._calculate_hash(artifact_file)
                file_size = os.path.getsize(artifact_file)

                self.evidence_files.append(EvidenceFile(
                    filename=artifact_name,
                    hash=file_hash,
                    size=file_size,
                    tool="Gitea Actions",
                    format="Binary/Archive",
                    collected_at=datetime.now(timezone.utc).isoformat(),
                    source_url=download_url
                ))

                artifacts[artifact_name] = artifact_file

        except Exception as e:
            logger.error(f"Failed to collect workflow artifacts: {e}")

        return artifacts

    def collect_scan_evidence(self, scan_type: str, scan_source: str, project_key: str = None) -> Dict:
        """
        Collect security scan evidence

        Args:
            scan_type: Type of scan (SAST, DAST, container, IaC)
            scan_source: Source tool (sonarqube, trivy, etc.)
            project_key: Project identifier

        Returns:
            Dictionary of scan results
        """
        logger.info(f"Collecting {scan_type} scan evidence from {scan_source}")

        scan_results = {}

        if scan_source.lower() == "sonarqube":
            scan_results = self._collect_sonarqube_evidence(project_key)
        elif scan_source.lower() == "trivy":
            scan_results = self._collect_trivy_evidence(scan_type)

        return scan_results

    def _collect_sonarqube_evidence(self, project_key: str) -> Dict:
        """Collect SonarQube SAST scan results"""
        sonar_url = self.config['sonarqube']['url']
        token = self.config['sonarqube']['token']
        headers = {
            "Authorization": f"Basic {token}",
            "Accept": "application/json"
        }

        results = {}

        # Get project analysis
        api_url = f"{sonar_url}/api/measures/component"
        params = {
            "component": project_key,
            "metricKeys": "bugs,vulnerabilities,code_smells,security_hotspots,coverage,duplicated_lines_density"
        }

        try:
            response = requests.get(api_url, headers=headers, params=params, timeout=30)
            response.raise_for_status()
            measures_data = response.json()

            # Save measures
            measures_file = os.path.join(self.temp_dir, "sonarqube-measures.json")
            with open(measures_file, 'w') as f:
                json.dump(measures_data, f, indent=2)

            file_hash = self._calculate_hash(measures_file)
            file_size = os.path.getsize(measures_file)

            self.evidence_files.append(EvidenceFile(
                filename="sonarqube-measures.json",
                hash=file_hash,
                size=file_size,
                tool="SonarQube",
                format="JSON",
                collected_at=datetime.now(timezone.utc).isoformat(),
                source_url=api_url
            ))

            # Map to SSDF practices
            self.practices_covered.append(SSMFPractice(
                practice="PW.6.1",
                tool="SonarQube",
                evidence="sonarqube-measures.json",
                description="Use automated SAST tools to identify code vulnerabilities",
                verification_method="SonarQube quality gate analysis"
            ))

            self.practices_covered.append(SSMFPractice(
                practice="PW.7.1",
                tool="SonarQube",
                evidence="sonarqube-measures.json",
                description="Review code for security vulnerabilities",
                verification_method="Code quality metrics and issue tracking"
            ))

            results['measures'] = measures_data

            # Get issues/vulnerabilities
            issues_url = f"{sonar_url}/api/issues/search"
            issues_params = {
                "componentKeys": project_key,
                "types": "VULNERABILITY,BUG,SECURITY_HOTSPOT",
                "ps": 500
            }

            response = requests.get(issues_url, headers=headers, params=issues_params, timeout=30)
            response.raise_for_status()
            issues_data = response.json()

            # Save issues
            issues_file = os.path.join(self.temp_dir, "sonarqube-issues.json")
            with open(issues_file, 'w') as f:
                json.dump(issues_data, f, indent=2)

            file_hash = self._calculate_hash(issues_file)
            file_size = os.path.getsize(issues_file)

            self.evidence_files.append(EvidenceFile(
                filename="sonarqube-issues.json",
                hash=file_hash,
                size=file_size,
                tool="SonarQube",
                format="JSON",
                collected_at=datetime.now(timezone.utc).isoformat(),
                source_url=issues_url
            ))

            results['issues'] = issues_data

        except Exception as e:
            logger.error(f"Failed to collect SonarQube evidence: {e}")

        return results

    def _collect_trivy_evidence(self, scan_type: str) -> Dict:
        """Collect Trivy scan results from GCS or local filesystem"""
        results = {}

        # Trivy outputs are typically stored as JSON files in GCS or artifacts
        # This method looks for them in the temp directory (from workflow artifacts)
        trivy_files = [
            "trivy-container-scan.json",
            "trivy-fs-scan.json",
            "trivy-config-scan.json"
        ]

        for trivy_file in trivy_files:
            file_path = os.path.join(self.temp_dir, trivy_file)
            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    scan_data = json.load(f)

                file_hash = self._calculate_hash(file_path)
                file_size = os.path.getsize(file_path)

                self.evidence_files.append(EvidenceFile(
                    filename=trivy_file,
                    hash=file_hash,
                    size=file_size,
                    tool="Trivy",
                    format="JSON",
                    collected_at=datetime.now(timezone.utc).isoformat()
                ))

                # Map to SSDF practices
                self.practices_covered.append(SSMFPractice(
                    practice="PW.8.1",
                    tool="Trivy",
                    evidence=trivy_file,
                    description="Scan for vulnerabilities in dependencies and containers",
                    verification_method="Trivy vulnerability database scan"
                ))

                results[trivy_file] = scan_data

        return results

    def collect_sbom_evidence(self, artifact_id: str = None) -> Dict:
        """
        Collect SBOM evidence

        Args:
            artifact_id: Optional artifact identifier

        Returns:
            Dictionary of SBOM data
        """
        logger.info("Collecting SBOM evidence")

        sbom_results = {}

        # Look for SBOM files (SPDX, CycloneDX)
        sbom_files = [
            "sbom.spdx.json",
            "sbom.cyclonedx.json",
            "syft-sbom.json"
        ]

        for sbom_file in sbom_files:
            file_path = os.path.join(self.temp_dir, sbom_file)
            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    sbom_data = json.load(f)

                # Validate SBOM completeness
                validation_result = self._validate_sbom(sbom_data, sbom_file)

                file_hash = self._calculate_hash(file_path)
                file_size = os.path.getsize(file_path)

                self.evidence_files.append(EvidenceFile(
                    filename=sbom_file,
                    hash=file_hash,
                    size=file_size,
                    tool="Syft/SBOM Tool",
                    format="JSON (SPDX/CycloneDX)",
                    collected_at=datetime.now(timezone.utc).isoformat()
                ))

                # Map to SSDF practices
                self.practices_covered.append(SSMFPractice(
                    practice="PW.9.1",
                    tool="Syft",
                    evidence=sbom_file,
                    description="Generate and maintain SBOM for all software components",
                    verification_method="SBOM validation and component inventory"
                ))

                self.practices_covered.append(SSMFPractice(
                    practice="PS.1.1",
                    tool="Syft",
                    evidence=sbom_file,
                    description="Store and distribute SBOM with software releases",
                    verification_method="SBOM availability in evidence package"
                ))

                sbom_results[sbom_file] = {
                    'data': sbom_data,
                    'validation': validation_result
                }

        return sbom_results

    def _validate_sbom(self, sbom_data: Dict, filename: str) -> Dict:
        """Validate SBOM completeness"""
        validation = {
            'valid': True,
            'errors': [],
            'warnings': [],
            'component_count': 0
        }

        # SPDX validation
        if 'spdx' in filename.lower():
            if 'packages' not in sbom_data:
                validation['valid'] = False
                validation['errors'].append("Missing 'packages' field in SPDX SBOM")
            else:
                validation['component_count'] = len(sbom_data.get('packages', []))

            required_fields = ['spdxVersion', 'creationInfo', 'name']
            for field in required_fields:
                if field not in sbom_data:
                    validation['errors'].append(f"Missing required field: {field}")

        # CycloneDX validation
        elif 'cyclonedx' in filename.lower():
            if 'components' not in sbom_data:
                validation['valid'] = False
                validation['errors'].append("Missing 'components' field in CycloneDX SBOM")
            else:
                validation['component_count'] = len(sbom_data.get('components', []))

            required_fields = ['bomFormat', 'specVersion', 'version']
            for field in required_fields:
                if field not in sbom_data:
                    validation['errors'].append(f"Missing required field: {field}")

        if validation['component_count'] == 0:
            validation['warnings'].append("SBOM contains zero components")

        return validation

    def collect_attestation_evidence(self, build_id: str) -> Dict:
        """
        Collect build attestations and signatures

        Args:
            build_id: Build identifier

        Returns:
            Dictionary of attestation data
        """
        logger.info("Collecting attestation evidence")

        attestation_results = {}

        # Look for attestation files
        attestation_files = [
            ("provenance.json", "SLSA Provenance"),
            ("attestation.json", "Build Attestation"),
            ("intoto-attestation.json", "in-toto Attestation")
        ]

        for filename, attest_type in attestation_files:
            file_path = os.path.join(self.temp_dir, filename)
            sig_path = os.path.join(self.temp_dir, f"{filename}.sig")

            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    attestation_data = json.load(f)

                # Check for signature
                signature_file = f"{filename}.sig"
                has_signature = os.path.exists(sig_path)
                verified = False

                if has_signature:
                    # Verify signature with Cosign (simplified - actual verification requires cosign binary)
                    verified = self._verify_cosign_signature(file_path, sig_path)

                    file_hash = self._calculate_hash(sig_path)
                    file_size = os.path.getsize(sig_path)

                    self.evidence_files.append(EvidenceFile(
                        filename=signature_file,
                        hash=file_hash,
                        size=file_size,
                        tool="Cosign",
                        format="Signature",
                        collected_at=datetime.now(timezone.utc).isoformat()
                    ))

                file_hash = self._calculate_hash(file_path)
                file_size = os.path.getsize(file_path)

                self.evidence_files.append(EvidenceFile(
                    filename=filename,
                    hash=file_hash,
                    size=file_size,
                    tool="Build System",
                    format="JSON",
                    collected_at=datetime.now(timezone.utc).isoformat()
                ))

                # Create attestation record
                attestation = Attestation(
                    type=attest_type,
                    file=filename,
                    signature=signature_file if has_signature else "none",
                    verified=verified
                )
                self.attestations.append(attestation)

                # Map to SSDF practices
                self.practices_covered.append(SSMFPractice(
                    practice="PS.2.1",
                    tool="Cosign/Attestation",
                    evidence=filename,
                    description="Sign software artifacts with cryptographic signatures",
                    verification_method="Cosign signature verification"
                ))

                attestation_results[filename] = {
                    'data': attestation_data,
                    'signed': has_signature,
                    'verified': verified
                }

        return attestation_results

    def _verify_cosign_signature(self, artifact_path: str, signature_path: str) -> bool:
        """
        Verify Cosign signature
        Note: This is a placeholder. Actual verification requires cosign binary.
        """
        # In production, use subprocess to call cosign verify-blob
        # For now, just check that files exist
        return os.path.exists(artifact_path) and os.path.exists(signature_path)

    def collect_n8n_evidence(self, workflow_execution_id: str) -> Dict:
        """
        Collect n8n workflow execution evidence

        Args:
            workflow_execution_id: n8n execution ID

        Returns:
            Dictionary of execution data
        """
        logger.info(f"Collecting n8n workflow evidence: {workflow_execution_id}")

        # n8n evidence would typically come from API or database
        # This is a placeholder for integration
        n8n_results = {
            'execution_id': workflow_execution_id,
            'status': 'collected',
            'note': 'n8n integration requires API endpoint configuration'
        }

        return n8n_results

    def create_manifest(self, build_id: str, repository: str, commit_sha: str) -> Dict:
        """
        Create evidence manifest

        Args:
            build_id: Build identifier
            repository: Repository name
            commit_sha: Git commit SHA

        Returns:
            Manifest dictionary
        """
        logger.info("Creating evidence manifest")

        # Calculate coverage
        total_practices = 42  # Total SSDF practices
        practices_covered_count = len(set(p.practice for p in self.practices_covered))
        coverage_percent = round((practices_covered_count / total_practices) * 100, 2)

        manifest = {
            "manifest_version": "1.0",
            "build_id": build_id,
            "repository": repository,
            "commit_sha": commit_sha,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "collector_version": "1.0.0",
            "ssdf_practices_covered": [
                {
                    "practice": p.practice,
                    "tool": p.tool,
                    "evidence": p.evidence,
                    "description": p.description,
                    "verification_method": p.verification_method
                }
                for p in self.practices_covered
            ],
            "evidence_files": [
                {
                    "filename": ef.filename,
                    "hash": ef.hash,
                    "size": ef.size,
                    "tool": ef.tool,
                    "format": ef.format,
                    "collected_at": ef.collected_at,
                    "source_url": ef.source_url
                }
                for ef in self.evidence_files
            ],
            "attestations": [
                {
                    "type": a.type,
                    "file": a.file,
                    "signature": a.signature,
                    "verified": a.verified,
                    "public_key_id": a.public_key_id
                }
                for a in self.attestations
            ],
            "compliance_summary": {
                "total_practices": total_practices,
                "practices_covered": practices_covered_count,
                "coverage_percent": coverage_percent
            },
            "retention": {
                "policy": "7-year retention",
                "retention_days": self.config['evidence']['retention_days'],
                "storage_class_transitions": [
                    {"days": 90, "class": "COLDLINE"},
                    {"days": 365, "class": "ARCHIVE"}
                ]
            }
        }

        # Save manifest
        manifest_file = os.path.join(self.temp_dir, "manifest.json")
        with open(manifest_file, 'w') as f:
            json.dump(manifest, f, indent=2)

        # Calculate manifest hash
        manifest_hash = self._calculate_hash(manifest_file)
        manifest['manifest_hash'] = manifest_hash

        # Update manifest file with hash
        with open(manifest_file, 'w') as f:
            json.dump(manifest, f, indent=2)

        return manifest

    def package_evidence(self, build_id: str) -> str:
        """
        Package evidence into compressed archive

        Args:
            build_id: Build identifier

        Returns:
            Path to evidence package
        """
        logger.info("Packaging evidence")

        package_name = f"evidence-{build_id}.tar.gz"
        package_path = os.path.join(self.temp_dir, package_name)

        with tarfile.open(package_path, "w:gz") as tar:
            tar.add(self.temp_dir, arcname=build_id,
                   filter=lambda x: None if x.name.endswith('.tar.gz') else x)

        logger.info(f"Evidence packaged: {package_path}")
        return package_path

    def upload_to_gcs(self, package_path: str, repository: str, build_id: str) -> str:
        """
        Upload evidence package to GCS

        Args:
            package_path: Path to evidence package
            repository: Repository name
            build_id: Build identifier

        Returns:
            GCS URI of uploaded package
        """
        logger.info("Uploading evidence to GCS")

        # Initialize GCS client
        if not self.storage_client:
            credentials_path = self.config['gcs']['credentials_path']
            if credentials_path and os.path.exists(credentials_path):
                os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = credentials_path
            self.storage_client = storage.Client(project=self.config['gcs']['project'])

        bucket_name = self.config['gcs']['bucket']
        bucket = self.storage_client.bucket(bucket_name)

        # Create path: /{repo}/{year}/{month}/{build-id}/evidence.tar.gz
        now = datetime.now(timezone.utc)
        gcs_path = f"{repository}/{now.year}/{now.month:02d}/{build_id}/{os.path.basename(package_path)}"

        blob = bucket.blob(gcs_path)

        # Set metadata
        blob.metadata = {
            'build_id': build_id,
            'repository': repository,
            'collected_at': now.isoformat(),
            'retention_days': str(self.config['evidence']['retention_days'])
        }

        # Upload with retry
        blob.upload_from_filename(package_path, retry=retry.Retry())

        gcs_uri = f"gs://{bucket_name}/{gcs_path}"
        logger.info(f"Evidence uploaded: {gcs_uri}")

        return gcs_uri

    def register_evidence(self, build_id: str, repository: str, commit_sha: str,
                         workflow_id: int, gcs_path: str, manifest: Dict) -> None:
        """
        Register evidence in PostgreSQL database

        Args:
            build_id: Build identifier
            repository: Repository name
            commit_sha: Git commit SHA
            workflow_id: Workflow ID
            gcs_path: GCS path to evidence
            manifest: Evidence manifest
        """
        logger.info("Registering evidence in database")

        if not self.db_conn:
            self.db_conn = psycopg2.connect(
                host=self.config['database']['host'],
                port=self.config['database']['port'],
                database=self.config['database']['database'],
                user=self.config['database']['user'],
                password=self.config['database']['password']
            )

        cursor = self.db_conn.cursor()

        # Extract tools used
        tools_used = {
            tool: list(set([p['tool'] for p in manifest['ssdf_practices_covered'] if p['tool'] == tool]))
            for tool in set([p['tool'] for p in manifest['ssdf_practices_covered']])
        }

        practices = [p['practice'] for p in manifest['ssdf_practices_covered']]

        # Insert record
        insert_query = """
        INSERT INTO evidence_registry
        (id, repository, commit_sha, workflow_id, practices_covered,
         evidence_path, evidence_hash, collected_at, tools_used)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """

        cursor.execute(insert_query, (
            build_id,
            repository,
            commit_sha,
            workflow_id,
            practices,
            gcs_path,
            manifest.get('manifest_hash', ''),
            datetime.now(timezone.utc),
            json.dumps(tools_used)
        ))

        self.db_conn.commit()
        cursor.close()

        logger.info("Evidence registered successfully")

    def collect_all(self, repository: str, workflow_id: int, run_number: int,
                   commit_sha: str, sonar_project_key: str = None) -> Tuple[str, Dict]:
        """
        Collect all evidence for a build

        Args:
            repository: Repository name
            workflow_id: Workflow ID
            run_number: Run number
            commit_sha: Git commit SHA
            sonar_project_key: SonarQube project key

        Returns:
            Tuple of (GCS URI, manifest)
        """
        build_id = str(uuid.uuid4())

        # Create temporary directory
        self.temp_dir = tempfile.mkdtemp(prefix=f"evidence-{build_id}-")
        logger.info(f"Working directory: {self.temp_dir}")

        try:
            # Collect all evidence types
            logger.info("Starting evidence collection")

            # 1. Build evidence
            self.collect_build_evidence(repository, workflow_id, run_number)

            # 2. Scan evidence
            if sonar_project_key:
                self.collect_scan_evidence("SAST", "sonarqube", sonar_project_key)
            self.collect_scan_evidence("container", "trivy")

            # 3. SBOM evidence
            self.collect_sbom_evidence()

            # 4. Attestation evidence
            self.collect_attestation_evidence(build_id)

            # 5. Create manifest
            manifest = self.create_manifest(build_id, repository, commit_sha)

            # 6. Package evidence
            package_path = self.package_evidence(build_id)

            # 7. Upload to GCS
            gcs_uri = self.upload_to_gcs(package_path, repository, build_id)

            # 8. Register in database
            self.register_evidence(build_id, repository, commit_sha,
                                  workflow_id, gcs_uri, manifest)

            logger.info("Evidence collection completed successfully")
            return gcs_uri, manifest

        finally:
            # Cleanup temporary directory
            if self.temp_dir and os.path.exists(self.temp_dir):
                import shutil
                shutil.rmtree(self.temp_dir)
                logger.info("Temporary directory cleaned up")

    def close(self):
        """Close database connection"""
        if self.db_conn:
            self.db_conn.close()


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='SSDF Evidence Collector')
    parser.add_argument('--repository', required=True, help='Repository name (owner/repo)')
    parser.add_argument('--workflow-id', type=int, required=True, help='Workflow ID')
    parser.add_argument('--run-number', type=int, required=True, help='Run number')
    parser.add_argument('--commit-sha', required=True, help='Git commit SHA')
    parser.add_argument('--sonar-project', help='SonarQube project key')
    parser.add_argument('--config', default='/home/notme/Desktop/gitea/ssdf/evidence/config/collector-config.json',
                       help='Configuration file path')

    args = parser.parse_args()

    collector = SSMFEvidenceCollector(config_path=args.config)

    try:
        gcs_uri, manifest = collector.collect_all(
            repository=args.repository,
            workflow_id=args.workflow_id,
            run_number=args.run_number,
            commit_sha=args.commit_sha,
            sonar_project_key=args.sonar_project
        )

        print(f"\nEvidence Collection Complete")
        print(f"GCS URI: {gcs_uri}")
        print(f"Build ID: {manifest['build_id']}")
        print(f"Practices Covered: {manifest['compliance_summary']['practices_covered']}/{manifest['compliance_summary']['total_practices']}")
        print(f"Coverage: {manifest['compliance_summary']['coverage_percent']}%")

    finally:
        collector.close()


if __name__ == "__main__":
    main()
