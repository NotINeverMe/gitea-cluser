# Security & Deployment Validation

Purpose
- Provide a repeatable capability for security scanning, deployment validation, and light penetration testing for the Gitea stack and related services.
- Generate auditable evidence artifacts under `compliance/evidence/security/`.

What’s included
- Make targets for SAST, dependency/container scans, secrets scans, DAST (OWASP ZAP, Nuclei), and deployment validation.
- Docker-based runners to avoid host tool drift (no host installs required beyond Docker).
- Evidence packaging with SHA256 hashes.

Infrastructure coverage
- Infra checks: Terraform security scans (Checkov, tfsec, Terrascan) + optional GCP enumeration of firewall rules, external IPs, and instances when `gcloud` is available.
- Infra pen tests: Nmap service discovery and TLS/cipher checks (testssl.sh) against configured infra targets.

Quick start
1) Copy env template and set target URLs (never commit secrets):
   cp security/.env.example security/.env
   # edit security/.env (GITEA_URL, ATLANTIS_URL, DASHBOARD_URL, etc.)

2) Run a full suite (generates evidence):
   make -C security suite

3) Or run components:
 make -C security sast secrets deps dast validate
  # Infra checks and pen tests
  make -C security infra-checks
  make -C security infra-pen
  make -C security infra

Evidence outputs
- compliance/evidence/security/
  - semgrep.json, bandit.json, hadolint.json
  - gitleaks.json
  - trivy-fs.json (and optional image scans)
  - zap-<target>-<ts>.html/json, nuclei-<ts>.json
  - validate-<target>-<ts>.md (status, headers, TLS summary)

Notes
- Network access is required for DAST and some containerized scans (image pulls). Configure or run locally as appropriate.
- Keep scans read-only; do not run active ZAP scans by default. Use baseline mode.
- Align with repo compliance guidance: save artifacts and include in evidence bundles when changes are compliance-impacting.

Targets overview
- sast: Semgrep, Bandit (dashboard/), Hadolint
- deps: Trivy filesystem (vuln/secret/config)
- secrets: Gitleaks
- dast: ZAP baseline, Nuclei
- validate: HTTP status, headers, TLS summary
- infra-checks: Checkov, tfsec, Terrascan + optional GCP enum
- infra-pen: Nmap (TCP service discovery), testssl.sh
- infra: infra-checks + infra-pen
