# Phase 1A Validation and Testing Procedures

## Executive Summary

This document provides comprehensive validation and testing procedures for Phase 1A of the Gitea DevSecOps platform implementation. All tests are designed to verify compliance with CMMC 2.0 Level 2 and NIST SP 800-171 Rev. 2 requirements.

## Table of Contents

1. [Validation Overview](#validation-overview)
2. [Service Validation Tests](#service-validation-tests)
3. [Security Scanning Validation](#security-scanning-validation)
4. [Workflow Execution Tests](#workflow-execution-tests)
5. [Compliance Verification](#compliance-verification)
6. [Performance Testing](#performance-testing)
7. [Integration Testing](#integration-testing)
8. [Acceptance Criteria](#acceptance-criteria)

## Validation Overview

### Test Environment

- **Platform**: Gitea DevSecOps Phase 1A
- **Components**: SonarQube, Semgrep, Trivy, Grype, Terraform Security
- **Duration**: 2-3 hours for complete validation
- **Evidence Required**: Yes, SHA-256 hashed logs

### Test Categories

1. **Functional Testing**: Verify all components work as expected
2. **Security Testing**: Validate security controls implementation
3. **Compliance Testing**: Ensure CMMC/NIST requirements are met
4. **Integration Testing**: Verify component interactions
5. **Performance Testing**: Baseline performance metrics

## Service Validation Tests

### Test 1.1: Docker Services Health Check

**Objective**: Verify all Docker services are running and healthy

**Test Steps**:
```bash
# Check service status
docker-compose ps

# Verify health status
docker-compose ps | grep -E "healthy|running"

# Check resource usage
docker stats --no-stream
```

**Expected Results**:
- All services show "healthy" or "running" status
- No services in "exited" or "error" state
- Resource usage within acceptable limits

**Evidence Collection**:
```bash
docker-compose ps > evidence/service-status-$(date +%Y%m%d-%H%M%S).log
sha256sum evidence/service-status-*.log > evidence/service-status.sha256
```

### Test 1.2: SonarQube API Validation

**Objective**: Verify SonarQube API is responsive and configured correctly

**Test Steps**:
```bash
# Check system status
curl -s http://localhost:9000/api/system/status | jq .

# Verify authentication
curl -s -u admin:$SONAR_ADMIN_PASSWORD \
  http://localhost:9000/api/authentication/validate | jq .

# List quality gates
curl -s -u admin:$SONAR_ADMIN_PASSWORD \
  http://localhost:9000/api/qualitygates/list | jq .
```

**Expected Results**:
```json
{
  "status": "UP",
  "valid": true,
  "qualitygates": [
    {
      "name": "CMMC-NIST-Security",
      "isDefault": false
    }
  ]
}
```

### Test 1.3: Trivy Server Validation

**Objective**: Verify Trivy server is operational

**Test Steps**:
```bash
# Test Trivy version
docker exec trivy-server trivy version

# Test vulnerability database
docker exec trivy-server trivy image --download-db-only

# Scan a test image
docker exec trivy-server trivy image alpine:latest
```

**Expected Results**:
- Version information displayed
- Database download successful
- Test scan completes without errors

## Security Scanning Validation

### Test 2.1: SAST Scanning with SonarQube

**Objective**: Validate SonarQube can detect security vulnerabilities

**Test Setup**:
```python
# Create test file: vulnerable_code.py
import os
import sqlite3

# CWE-798: Hardcoded credentials
password = "admin123"
api_key = "sk_live_abcd1234"

# CWE-89: SQL Injection
def get_user(user_id):
    conn = sqlite3.connect('database.db')
    query = f"SELECT * FROM users WHERE id = {user_id}"
    return conn.execute(query)

# CWE-78: OS Command Injection
def run_command(user_input):
    os.system(f"echo {user_input}")
```

**Test Execution**:
```bash
# Run SonarQube scan
sonar-scanner \
  -Dsonar.projectKey=test-security \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.token=$SONAR_TOKEN
```

**Expected Results**:
- Hardcoded credentials detected (Critical)
- SQL injection vulnerability detected (Critical)
- Command injection detected (Critical)
- Quality gate fails

### Test 2.2: Semgrep Advanced Analysis

**Objective**: Verify Semgrep detects complex security patterns

**Test Setup**:
```javascript
// Create test file: vulnerable_app.js
const express = require('express');
const app = express();

// CWE-79: XSS vulnerability
app.get('/user', (req, res) => {
    res.send(`<h1>Hello ${req.query.name}</h1>`);
});

// CWE-918: SSRF vulnerability
app.get('/fetch', (req, res) => {
    const url = req.query.url;
    fetch(url).then(response => res.send(response));
});

// CWE-502: Deserialization
app.post('/data', (req, res) => {
    const data = JSON.parse(req.body.data);
    eval(data.code);
});
```

**Test Execution**:
```bash
# Run Semgrep scan
semgrep --config=auto \
  --config=p/security-audit \
  --config=p/owasp-top-ten \
  --json vulnerable_app.js
```

**Expected Results**:
- XSS vulnerability identified
- SSRF vulnerability detected
- Unsafe deserialization flagged
- Minimum 3 HIGH severity findings

### Test 2.3: Container Security Scanning

**Objective**: Validate container vulnerability detection

**Test Setup**:
```dockerfile
# Create test Dockerfile with vulnerabilities
FROM node:10-alpine  # Old version with vulnerabilities
RUN apk add --no-cache curl wget
USER root  # Running as root
EXPOSE 22 23 3389  # Unnecessary ports
COPY . /app
RUN npm install --production
CMD ["node", "app.js"]
```

**Test Execution**:
```bash
# Build test image
docker build -t test-vulnerable:latest .

# Scan with Trivy
trivy image test-vulnerable:latest

# Scan with Grype
grype test-vulnerable:latest
```

**Expected Results**:
- Multiple CVEs detected in base image
- Configuration issues identified
- Security misconfigurations flagged
- At least 5 HIGH/CRITICAL vulnerabilities

### Test 2.4: Terraform Security Validation

**Objective**: Verify Terraform security policy enforcement

**Test Setup**:
```hcl
# Create test file: insecure.tf
resource "google_compute_firewall" "bad_firewall" {
  name    = "allow-all"
  network = "default"

  # CMMC violation: unrestricted access
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
}

resource "google_storage_bucket" "insecure_bucket" {
  name     = "test-bucket"
  location = "US"

  # NIST violation: no encryption
  # Missing: encryption configuration
}

resource "google_project_iam_member" "excessive_permissions" {
  project = "my-project"
  role    = "roles/owner"  # Overly permissive
  member  = "allUsers"     # Public access
}
```

**Test Execution**:
```bash
# Run Checkov
checkov -f insecure.tf --framework terraform

# Run tfsec
tfsec insecure.tf

# Run Terrascan
terrascan scan -i terraform -f insecure.tf
```

**Expected Results**:
- Firewall rule violation detected
- Missing encryption flagged
- IAM permission issues identified
- Policy violations for CMMC/NIST

## Workflow Execution Tests

### Test 3.1: End-to-End Workflow Validation

**Objective**: Verify complete workflow execution

**Test Steps**:
```bash
# Create test repository
mkdir test-security-repo
cd test-security-repo
git init

# Add vulnerable code
cat > app.py << 'EOF'
import os
password = "test123"
os.system(f"echo {input()}")
EOF

# Copy workflows
cp -r /home/notme/Desktop/gitea/.gitea/workflows .gitea/

# Commit and push
git add .
git commit -m "Test security workflows"
git remote add origin <gitea-repo-url>
git push -u origin main
```

**Expected Results**:
- All workflows trigger automatically
- Security findings reported
- Google Chat notifications sent
- Evidence files generated

### Test 3.2: Parallel Workflow Execution

**Objective**: Test concurrent workflow execution

**Test Steps**:
```bash
# Trigger multiple workflows simultaneously
for i in {1..5}; do
  git commit --allow-empty -m "Test parallel execution $i"
  git push &
done

wait
```

**Expected Results**:
- All workflows execute without conflicts
- Resource usage remains stable
- No workflow failures due to concurrency

## Compliance Verification

### Test 4.1: CMMC 2.0 Level 2 Compliance

**Objective**: Verify CMMC control implementation

**Test Checklist**:

| Control | Test | Pass Criteria |
|---------|------|---------------|
| CA.L2-3.12.4 | Run security scan | Vulnerabilities detected and reported |
| RA.L2-3.11.2 | Execute vulnerability scan | Container vulnerabilities identified |
| SI.L2-3.14.2 | Check malicious code detection | Malware patterns detected |
| AU.L2-3.3.1 | Verify audit logging | All scans generate evidence logs |
| SC.L2-3.13.8 | Check encryption validation | Unencrypted resources flagged |

**Verification Script**:
```bash
#!/bin/bash
# CMMC compliance verification

echo "CMMC 2.0 Level 2 Compliance Test"
echo "================================="

# Test each control
controls=(
  "CA.L2-3.12.4:sonarqube-scan"
  "RA.L2-3.11.2:container-security"
  "SI.L2-3.14.2:semgrep-sast"
  "AU.L2-3.3.1:evidence-logs"
  "SC.L2-3.13.8:terraform-security"
)

for control in "${controls[@]}"; do
  IFS=':' read -r control_id workflow <<< "$control"
  echo -n "Testing $control_id... "

  if grep -q "$control_id" .gitea/workflows/${workflow}.yml; then
    echo "✓ PASS"
  else
    echo "✗ FAIL"
  fi
done
```

### Test 4.2: NIST SP 800-171 Compliance

**Objective**: Verify NIST control implementation

**Test Checklist**:

| Control | Requirement | Verification |
|---------|------------|--------------|
| 3.11.2 | Vulnerability scanning | Trivy/Grype operational |
| 3.14.1 | Identify flaws | SonarQube/Semgrep active |
| 3.14.2 | Report flaws | Notifications configured |
| 3.14.3 | Monitor alerts | Google Chat integration |
| 3.4.1 | Baseline configs | Terraform policies enforced |

### Test 4.3: Evidence Chain Validation

**Objective**: Verify evidence generation and integrity

**Test Steps**:
```bash
# Check evidence generation
ls -la evidence/phase1a/

# Verify evidence hashes
cd evidence/phase1a
for file in *.log; do
  echo "Verifying $file..."
  sha256sum -c ${file%.log}.sha256
done

# Validate timestamp integrity
grep -E "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z" *.log
```

**Expected Results**:
- All evidence files have corresponding hash files
- Hash verification passes
- Timestamps in ISO 8601 format
- Evidence chain unbroken

## Performance Testing

### Test 5.1: Scan Performance Baseline

**Objective**: Establish performance baselines

**Test Script**:
```bash
#!/bin/bash
# Performance baseline test

echo "Performance Baseline Test"
echo "========================"

# Test SonarQube scan time
time docker exec sonarqube sonar-scanner \
  -Dsonar.projectKey=perf-test \
  -Dsonar.sources=/usr/src

# Test Trivy scan time
time docker exec trivy-server trivy image node:latest

# Test Semgrep scan time
time semgrep --config=auto /usr/src

# Resource usage during scan
docker stats --no-stream
```

**Acceptance Criteria**:
- SonarQube scan: < 5 minutes for 10K LOC
- Trivy scan: < 2 minutes per image
- Semgrep scan: < 3 minutes for 10K LOC
- Memory usage: < 4GB per scanner
- CPU usage: < 200% per scanner

### Test 5.2: Concurrent Load Testing

**Objective**: Test system under load

**Test Steps**:
```bash
# Simulate concurrent scans
for i in {1..10}; do
  (
    curl -X POST http://localhost:9000/api/ce/submit \
      -d "projectKey=test-$i" &
  )
done

wait

# Monitor system resources
docker stats --no-stream
```

**Expected Results**:
- All scans complete successfully
- No service crashes
- Response time < 10 seconds
- Queue management working

## Integration Testing

### Test 6.1: GitHub/GitLab Migration Test

**Objective**: Verify workflows can be migrated from GitHub/GitLab

**Test Steps**:
```bash
# Convert GitHub Action to Gitea
sed -i 's/uses: actions/uses: gitea/g' .github/workflows/*.yml

# Test converted workflow
act -W .gitea/workflows/sonarqube-scan.yml
```

**Expected Results**:
- Workflows execute with minimal changes
- All steps complete successfully
- Outputs match expected format

### Test 6.2: Google Chat Integration

**Objective**: Verify alert delivery to Google Chat

**Test Steps**:
```bash
# Send test alerts of each severity
for severity in CRITICAL HIGH MEDIUM LOW; do
  ./scripts/send-gchat-alert.sh \
    $severity \
    "Test Alert" \
    "Testing $severity alert delivery" \
    "http://localhost:3000"
done
```

**Expected Results**:
- All alerts delivered successfully
- Correct formatting for each severity
- Links functional
- No delivery delays > 5 seconds

## Acceptance Criteria

### Minimum Acceptance Criteria

All tests must pass the following criteria for Phase 1A to be considered complete:

1. **Service Availability**
   - [ ] All Docker services healthy
   - [ ] APIs responding within 2 seconds
   - [ ] No critical errors in logs

2. **Security Scanning**
   - [ ] SonarQube detecting test vulnerabilities
   - [ ] Semgrep identifying security patterns
   - [ ] Container scanners finding CVEs
   - [ ] Terraform policies enforcing rules

3. **Workflow Execution**
   - [ ] All workflows triggering correctly
   - [ ] Scans completing within timeouts
   - [ ] Results properly formatted

4. **Compliance**
   - [ ] CMMC controls verified
   - [ ] NIST requirements met
   - [ ] Evidence generation working
   - [ ] Hash validation passing

5. **Integration**
   - [ ] Google Chat notifications working
   - [ ] Gitea secrets accessible
   - [ ] SARIF reports generating

### Performance Benchmarks

| Metric | Target | Actual | Pass/Fail |
|--------|--------|--------|-----------|
| Service startup time | < 5 min | _____ | _____ |
| Scan completion (10K LOC) | < 10 min | _____ | _____ |
| Memory usage (idle) | < 2GB | _____ | _____ |
| Memory usage (scanning) | < 6GB | _____ | _____ |
| Disk usage | < 20GB | _____ | _____ |
| API response time | < 2 sec | _____ | _____ |

### Sign-off Checklist

- [ ] All functional tests passed
- [ ] Security vulnerabilities detected correctly
- [ ] Compliance requirements verified
- [ ] Performance within acceptable limits
- [ ] Integration points validated
- [ ] Evidence chain intact
- [ ] Documentation complete
- [ ] Team training conducted

## Test Execution Log

```
Test Execution Summary
======================
Date: ________________
Tester: ______________
Environment: _________

Test Results:
- Service Validation: [PASS/FAIL]
- Security Scanning: [PASS/FAIL]
- Workflow Execution: [PASS/FAIL]
- Compliance: [PASS/FAIL]
- Performance: [PASS/FAIL]
- Integration: [PASS/FAIL]

Issues Found:
1. _______________________
2. _______________________
3. _______________________

Remediation Actions:
1. _______________________
2. _______________________
3. _______________________

Overall Status: [PASS/FAIL]

Sign-off:
Technical Lead: __________ Date: ______
Security Lead: ___________ Date: ______
Compliance Officer: ______ Date: ______
```

## Appendix: Troubleshooting Guide

### Common Validation Failures

#### Issue: SonarQube not detecting vulnerabilities
```bash
# Check scanner configuration
cat sonar-project.properties

# Verify rules are activated
curl -u admin:$PASS http://localhost:9000/api/rules/search?activation=true

# Solution: Activate security rules
curl -X POST -u admin:$PASS \
  http://localhost:9000/api/qualityprofiles/activate_rule \
  -d "key=java:S2068&severity=CRITICAL"
```

#### Issue: Workflows not triggering
```bash
# Check runner status
docker logs gitea-runner

# Verify webhook configuration
gitea admin hook list

# Solution: Re-register runner
gitea actions register
```

#### Issue: Google Chat notifications failing
```bash
# Test webhook directly
curl -X POST $GCHAT_WEBHOOK_URL -H 'Content-Type: application/json' \
  -d '{"text":"Test"}'

# Check webhook format
echo $GCHAT_WEBHOOK_URL | grep -E "^https://chat.googleapis.com"

# Solution: Regenerate webhook in Google Chat
```

---

*Document Version: 1.0.0*
*Last Updated: 2024-01-15*
*Next Review: 2024-04-15*
*Classification: Internal Use*