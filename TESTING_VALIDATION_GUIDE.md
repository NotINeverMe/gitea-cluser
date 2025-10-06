# DevSecOps Platform Testing & Validation Guide

## Overview

This guide provides comprehensive testing and validation procedures for the Gitea DevSecOps platform to ensure all components are functioning correctly and meeting CMMC 2.0 and NIST SP 800-171 compliance requirements.

## Pre-Deployment Validation

### System Requirements Check

```bash
# Run automated system check
make check-requirements

# Manual verification
docker --version          # Should be 20.10+
docker-compose --version  # Should be 2.0+
terraform --version       # Should be 1.5+
packer --version         # Should be 1.9+
python3 --version        # Should be 3.11+
```

### Configuration Validation

```bash
# Validate all configuration files
make validate-configs

# Validate individual components
make validate-docker
make validate-terraform
make validate-packer
make validate-prometheus
make validate-grafana
```

## Component Testing

### 1. Phase 1A - Security Foundation

#### SonarQube Testing

```bash
# Deploy SonarQube
make deploy-sonarqube

# Wait for startup (60-90 seconds)
make wait-for-sonarqube

# Verify accessibility
curl -u admin:admin http://localhost:9000/api/system/status

# Expected output:
# {"id":"...","version":"10.2","status":"UP"}

# Test with sample project
cd tests/sample-projects/vulnerable-app
git init
git add .
git commit -m "Initial commit"

# Trigger scan via Gitea Actions
git push gitea main

# Check results
curl -u admin:admin "http://localhost:9000/api/measures/component?component=vulnerable-app&metricKeys=vulnerabilities,bugs,code_smells"
```

#### Container Security Testing

```bash
# Test Trivy scanner
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image alpine:3.17

# Test Grype scanner
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  anchore/grype alpine:3.17

# Test integration with Gitea Actions
cd tests/sample-projects/docker-app
git push gitea main

# Verify scan results in pipeline logs
make logs SERVICE=gitea-actions | grep -A 10 "trivy"
```

#### Terraform Security Testing

```bash
# Test Checkov
cd tests/sample-terraform
checkov -d . --framework terraform --output json

# Test tfsec
tfsec . --format json

# Test Terrascan
terrascan scan -t gcp -d .

# Test integrated workflow
git add .
git commit -m "Test Terraform security"
git push gitea main

# Verify security gates
make logs SERVICE=gitea-actions | grep -E "checkov|tfsec|terrascan"
```

**Expected Results:**
- SonarQube detects vulnerabilities in sample code
- Trivy/Grype identify CVEs in container images
- Checkov/tfsec/Terrascan flag policy violations
- Security gates block CRITICAL findings

### 2. n8n Workflow Automation

#### Workflow Import Test

```bash
# Import workflows
./scripts/setup-n8n.sh

# Verify import
curl -u admin:ChangeMe123! http://localhost:5678/api/v1/workflows

# Expected: Should return list including "DevSecOps Security and Compliance Automation"
```

#### Webhook Testing

```bash
# Test each event type
./scripts/test-n8n-workflows.sh vulnerability
./scripts/test-n8n-workflows.sh compliance
./scripts/test-n8n-workflows.sh gate-failure
./scripts/test-n8n-workflows.sh incident
./scripts/test-n8n-workflows.sh cost-alert

# Run all tests
./scripts/test-n8n-workflows.sh all
```

#### Google Chat Integration Test

```bash
# Configure webhooks
./scripts/configure-gchat-webhooks.sh

# Send test alert
curl -X POST http://localhost:5678/webhook/security-events \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "vulnerability",
    "severity": "CRITICAL",
    "component": "test-app",
    "cve_id": "CVE-2024-TEST",
    "cvss_score": 9.8,
    "scanner": "manual-test",
    "description": "Test critical vulnerability"
  }'

# Check Google Chat for card notification
```

**Expected Results:**
- All 5 workflow event types execute successfully
- Google Chat receives formatted card notifications
- Evidence artifacts stored in GCS with SHA-256 hashes
- Metrics exported to Prometheus

### 3. Packer Image Security

#### Template Validation

```bash
# Validate templates
cd packer/templates
packer validate ubuntu-22-04-cis.pkr.hcl
packer validate container-optimized.pkr.hcl

# Expected: "The configuration is valid."
```

#### Build and Scan Test

```bash
# Build test image (requires GCP credentials)
./scripts/packer-build.sh -p YOUR_PROJECT_ID ubuntu-22-04-cis

# Monitor build progress
tail -f logs/packer-build-*.log

# Verify image created
gcloud compute images list --filter="name:ubuntu-22-04-cis-*"

# Check scan results
cat output/packer-scan-results-*.json | jq '.Results[].Vulnerabilities | length'
```

#### CIS Hardening Verification

```bash
# Launch instance from image
gcloud compute instances create test-cis \
  --image=ubuntu-22-04-cis-latest \
  --zone=us-central1-a

# SSH and verify hardening
gcloud compute ssh test-cis --zone=us-central1-a

# Run checks
sudo systemctl status auditd      # Should be active
sudo ufw status                   # Should be active
grep "PermitRootLogin" /etc/ssh/sshd_config  # Should be "no"
```

**Expected Results:**
- Packer builds complete without errors
- No CRITICAL vulnerabilities in scan results
- CIS benchmark score ≥90%
- All hardening scripts executed successfully

### 4. Monitoring Stack (Prometheus + Grafana)

#### Deployment Test

```bash
# Deploy monitoring stack
make monitoring-deploy

# Wait for startup
sleep 30

# Check health
make monitoring-health
```

#### Prometheus Testing

```bash
# Verify targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Expected: All targets should show health: "up"

# Query test metrics
curl "http://localhost:9090/api/v1/query?query=up" | jq '.data.result'

# Test alerts
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts'
```

#### Grafana Testing

```bash
# Verify accessibility
curl http://localhost:3000/api/health

# Login test
curl -X POST http://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","password":"ChangeMe123!"}'

# List dashboards
curl -u admin:ChangeMe123! http://localhost:3000/api/search?type=dash-db

# Expected: Should list provisioned dashboards
```

#### Custom Exporter Testing

```bash
# Test SonarQube exporter
curl http://localhost:9091/metrics | grep sonarqube_

# Test security scan exporter
curl http://localhost:9092/metrics | grep security_

# Test compliance exporter
curl http://localhost:9093/metrics | grep compliance_
```

**Expected Results:**
- All Prometheus targets healthy
- Grafana accessible and dashboards loaded
- Custom exporters returning metrics
- Alerts configured and visible

### 5. Atlantis + Terragrunt GitOps

#### Atlantis Deployment Test

```bash
# Deploy Atlantis
make atlantis-deploy

# Check health
curl http://localhost:4141/healthz

# Expected: {"status":"ok"}
```

#### Gitea Webhook Test

```bash
# Configure webhook manually or via script
./scripts/setup-atlantis.sh

# Verify webhook registered
curl -u $GITEA_USER:$GITEA_TOKEN \
  http://localhost:3000/api/v1/repos/$USER/terraform-test/hooks

# Expected: Should show Atlantis webhook URL
```

#### Terragrunt Workflow Test

```bash
# Create test PR
cd tests/sample-terraform
git checkout -b test-atlantis

# Make a change
cat >> main.tf <<EOF
resource "null_resource" "test" {
  triggers = {
    timestamp = timestamp()
  }
}
EOF

git add main.tf
git commit -m "Test Atlantis workflow"
git push origin test-atlantis

# Create PR via Gitea UI or API
# Atlantis should automatically comment with plan output

# Check Atlantis logs
make atlantis-logs | tail -50
```

#### Policy Validation Test

```bash
# Test OPA policies
cd atlantis/policies
conftest test --policy cmmc-nist.rego tests/test-plan.json

# Expected: Policy violations should be reported
```

**Expected Results:**
- Atlantis comments on PR with plan output
- Checkov/tfsec security scans complete
- Infracost provides cost estimate
- OPA policies validated
- Evidence stored in GCS

### 6. GCP Evidence Collection

#### Collector Deployment Test

```bash
# Deploy collectors
cd evidence-collection
./setup-gcp-environment.sh
docker-compose -f docker-compose-collectors.yml up -d

# Check logs
docker-compose -f docker-compose-collectors.yml logs -f
```

#### Collection Test

```bash
# Run collectors manually
python3 gcp-scc-collector.py --project YOUR_PROJECT_ID
python3 gcp-asset-inventory.py --project YOUR_PROJECT_ID
python3 gcp-iam-evidence.py --project YOUR_PROJECT_ID
python3 gcp-encryption-audit.py --project YOUR_PROJECT_ID

# Verify output
ls -lh output/

# Validate evidence
python3 validate-evidence.py --directory output/

# Check GCS upload
gsutil ls gs://compliance-evidence-your-org/
```

**Expected Results:**
- All collectors run without errors
- Evidence artifacts created in output/
- SHA-256 hashes generated
- Evidence uploaded to GCS successfully

## Integration Testing

### End-to-End Workflow Tests

#### Test 1: Code Commit → Security Scan → Notification

```bash
# 1. Create vulnerable code
cd tests/sample-projects/vulnerable-app
cat > app.py <<EOF
import pickle
import os

def unsafe_deserialize(data):
    return pickle.loads(data)  # Insecure deserialization

def command_injection(user_input):
    os.system(f"echo {user_input}")  # Command injection

if __name__ == "__main__":
    unsafe_deserialize(b"test")
    command_injection("test")
EOF

# 2. Commit and push
git add app.py
git commit -m "Add vulnerable code"
git push gitea main

# 3. Wait for pipeline (30-60 seconds)
sleep 60

# 4. Verify results
# - Check Gitea Actions for pipeline status
# - Check Google Chat for CRITICAL alert
# - Check GCS for evidence artifacts
# - Check Grafana dashboard for metrics

# Automated verification
make test-e2e-scanning
```

**Expected Results:**
- Gitea Actions pipeline runs
- SonarQube/Semgrep detect vulnerabilities
- n8n workflow triggers
- Google Chat alert sent to #security-alerts
- Evidence stored in GCS with hash
- Prometheus metrics updated
- Grafana dashboard shows new vulnerabilities

#### Test 2: Terraform PR → GitOps → Policy Enforcement

```bash
# 1. Create non-compliant Terraform
cd tests/sample-terraform
cat > non-compliant.tf <<EOF
resource "google_storage_bucket" "bad" {
  name     = "insecure-bucket-test"
  location = "US"

  # Missing encryption
  # Missing versioning
  # Missing logging
}

resource "google_compute_instance" "bad" {
  name         = "insecure-vm"
  machine_type = "n1-standard-1"
  zone         = "us-central1-a"

  # Missing OS Login
  # Missing Shielded VM
  # Has external IP (violation)
}
EOF

# 2. Create PR
git checkout -b test-compliance
git add non-compliant.tf
git commit -m "Non-compliant infrastructure"
git push origin test-compliance

# 3. Create PR in Gitea UI

# 4. Wait for Atlantis (15-30 seconds)

# 5. Verify results
# - Atlantis comments on PR
# - Checkov reports violations
# - tfsec reports security issues
# - OPA policy blocks non-compliant resources
# - Merge is blocked

# Automated verification
make test-e2e-gitops
```

**Expected Results:**
- Atlantis plan completes
- Security scans identify violations
- OPA policies fail with clear messages
- Infracost estimates cost
- PR shows all results in comments
- Merge blocked until fixed

#### Test 3: Packer Build → Image Scan → Registry

```bash
# 1. Trigger Packer build
cd packer/templates
git add ubuntu-22-04-cis.pkr.hcl
git commit -m "Update Packer template"
git push gitea main

# 2. Wait for build (10-15 minutes for GCP)

# 3. Monitor progress
tail -f logs/packer-build-*.log

# 4. Verify results
# - Image built successfully
# - Trivy scan completed
# - Grype scan completed
# - CIS validation passed
# - Image published to Artifact Registry
# - Evidence collected

# Automated verification
make test-e2e-packer
```

**Expected Results:**
- Packer build succeeds
- No CRITICAL vulnerabilities
- CIS score ≥90%
- Image tagged with metadata
- Evidence in GCS
- Google Chat success notification

## Compliance Validation

### Evidence Collection Verification

```bash
# Run compliance validation
make compliance-check

# Manual verification
python3 evidence-collection/validate-evidence.py \
  --bucket gs://compliance-evidence-your-org \
  --framework CMMC_2.0 \
  --control SI.L2-3.14.1

# Verify retention
gsutil lifecycle get gs://compliance-evidence-your-org

# Check manifest integrity
python3 evidence-collection/manifest-generator.py \
  --verify manifests/latest.json
```

**Expected Results:**
- All evidence artifacts have valid SHA-256 hashes
- Evidence mapped to correct controls
- Retention policies enforced
- Manifest consistent with GCS contents

### Control Coverage Assessment

```bash
# Generate coverage report
make compliance-report

# Review control mappings
cat compliance/CONTROL_IMPLEMENTATION_MATRIX.md | \
  grep "Implementation Status: Implemented" | wc -l

# Expected: Should show 89%+ implementation

# Review gaps
cat compliance/GAP_ANALYSIS.md
```

**Expected Results:**
- 89% automated CMMC 2.0 control coverage
- All gaps documented with POA&M
- Evidence artifacts for implemented controls
- Assessor-ready documentation

## Performance Testing

### Load Testing

```bash
# Test SonarQube under load
cd tests/performance
./load-test-sonarqube.sh 10  # 10 concurrent scans

# Test n8n workflow throughput
./load-test-n8n.sh 100  # 100 events/minute

# Test Prometheus query performance
./load-test-prometheus.sh

# Test Atlantis concurrent plans
./load-test-atlantis.sh 5  # 5 concurrent PRs
```

### Resource Utilization

```bash
# Monitor resource usage
docker stats

# Expected:
# - SonarQube: <4GB RAM
# - PostgreSQL (all): <2GB RAM total
# - Prometheus: <1GB RAM
# - Grafana: <500MB RAM
# - n8n: <500MB RAM
# - Atlantis: <500MB RAM
```

## Security Testing

### Vulnerability Scanning

```bash
# Scan all Docker images
make security-scan-images

# Scan infrastructure code
make security-scan-terraform

# Scan Python code
bandit -r evidence-collection/
bandit -r monitoring/exporters/

# Scan shell scripts
shellcheck scripts/*.sh
```

### Secrets Detection

```bash
# Check for exposed secrets
trufflehog git file://. --json

# Expected: No secrets found

# Validate secret management
grep -r "password\|token\|secret\|key" . \
  --exclude-dir={.git,node_modules} \
  --exclude="*.md" \
  --exclude="*.example"

# Expected: Only template/example files
```

### Network Security

```bash
# Verify network isolation
docker network inspect gitea_default
docker network inspect gitea_monitoring
docker network inspect gitea_atlantis

# Test external connectivity
docker run --rm --network=gitea_data alpine ping -c 1 8.8.8.8

# Expected: Should fail (no external access from data tier)
```

## Acceptance Testing Checklist

### Functional Requirements

- [ ] All Docker services start successfully
- [ ] Gitea Actions pipelines execute
- [ ] SonarQube scans detect vulnerabilities
- [ ] Trivy/Grype identify CVEs
- [ ] Checkov/tfsec enforce policies
- [ ] n8n workflows process events
- [ ] Google Chat receives notifications
- [ ] Prometheus collects metrics
- [ ] Grafana displays dashboards
- [ ] Atlantis responds to PRs
- [ ] Packer builds complete
- [ ] Evidence stored in GCS with hashes

### Security Requirements

- [ ] TLS/HTTPS configured on all public endpoints
- [ ] No default passwords in production
- [ ] Secrets managed via Gitea Secrets
- [ ] Network isolation enforced
- [ ] CRITICAL vulnerabilities blocked
- [ ] Audit logging enabled
- [ ] Evidence integrity verified

### Compliance Requirements

- [ ] 89%+ CMMC 2.0 control coverage
- [ ] Evidence collection automated
- [ ] 90-day metric retention
- [ ] 7-year evidence retention
- [ ] Control mappings documented
- [ ] POA&M for all gaps
- [ ] Assessor-ready documentation

### Performance Requirements

- [ ] SonarQube scans complete in <5 minutes
- [ ] Container scans complete in <2 minutes
- [ ] Terraform plans complete in <30 seconds
- [ ] Packer builds complete in <15 minutes
- [ ] n8n workflows process in <5 seconds
- [ ] Grafana dashboards load in <2 seconds

## Continuous Validation

### Daily Checks

```bash
# Run daily validation
make validate-daily

# Includes:
# - Service health checks
# - Backup verification
# - Evidence collection status
# - Metric retention compliance
# - Alert status
```

### Weekly Checks

```bash
# Run weekly validation
make validate-weekly

# Includes:
# - Security scan updates
# - Compliance coverage review
# - Performance metrics analysis
# - Cost optimization review
```

### Monthly Checks

```bash
# Run monthly validation
make validate-monthly

# Includes:
# - Full integration testing
# - Compliance gap assessment
# - Documentation review
# - Security posture evaluation
```

## Troubleshooting Failed Tests

### Common Issues

1. **Service Won't Start**
   ```bash
   # Check logs
   docker-compose logs SERVICE_NAME

   # Check resources
   docker stats

   # Restart service
   docker-compose restart SERVICE_NAME
   ```

2. **Webhook Not Received**
   ```bash
   # Verify webhook configuration
   curl http://localhost:5678/healthz

   # Check firewall/network
   docker network inspect gitea_default

   # Test connectivity
   docker exec gitea curl http://n8n:5678/healthz
   ```

3. **Security Scan Failing**
   ```bash
   # Update scanner databases
   docker pull aquasec/trivy:latest
   trivy image --download-db-only

   # Re-run scan
   make security-scan
   ```

4. **Evidence Upload Failing**
   ```bash
   # Check GCP credentials
   gcloud auth application-default print-access-token

   # Test GCS access
   gsutil ls gs://compliance-evidence-your-org

   # Check service account permissions
   gcloud projects get-iam-policy $PROJECT_ID
   ```

## Validation Report Template

```markdown
# DevSecOps Platform Validation Report

**Date:** YYYY-MM-DD
**Validated By:** [Name]
**Environment:** [Dev/Staging/Prod]

## Summary
- Total Tests: X
- Passed: Y
- Failed: Z
- Pass Rate: Y/X%

## Component Status
- [ ] Phase 1A (Security Foundation)
- [ ] n8n Workflow Automation
- [ ] Packer Image Security
- [ ] Monitoring Stack
- [ ] Atlantis GitOps
- [ ] Evidence Collection

## Failed Tests
1. Test Name - Failure Reason - Remediation Plan

## Compliance Status
- CMMC Coverage: X%
- Evidence Collection: [Operational/Issues]
- Gaps: [Count] documented in POA&M

## Recommendations
1. ...
2. ...

## Sign-Off
- Technical Lead: _____________
- Compliance Officer: _____________
- Date: _____________
```

Save this report after each validation cycle for audit trails.
