package build.security

import future.keywords.contains
import future.keywords.if
import future.keywords.in

default allow := false

# Build Security Policy for SSDF Compliance
# Enforces security requirements for build processes

# Main allow rule - all conditions must pass
allow if {
    signed_commits
    sbom_generated
    no_critical_cves
    sufficient_reviewers
    valid_base_images
    no_secrets
}

# Require signed commits (PS.2.1)
signed_commits if {
    input.commit.signature != null
    input.commit.signature.verified == true
}

# Require SBOM generation (PW.9.2)
sbom_generated if {
    count(input.artifacts.sbom) > 0
    "spdx" in input.artifacts.sbom_formats
    "cyclonedx" in input.artifacts.sbom_formats
}

# Block builds with critical CVEs (PW.7.1)
no_critical_cves if {
    input.security.vulnerabilities.critical == 0
}

# Allow high severity CVEs only with approval
high_cves_with_approval if {
    input.security.vulnerabilities.high > 0
    input.security.vulnerabilities.high <= 5
    input.approval.security_team == true
}

# Require minimum code review approvals (PW.2.1)
sufficient_reviewers if {
    count(input.pull_request.approvals) >= 2
    input.pull_request.status == "approved"
}

# Validate container base images (PS.3.1)
valid_base_images if {
    every image in input.docker.base_images {
        image in allowed_base_images
    }
}

# Allowed base images allowlist
allowed_base_images := {
    "alpine:3.18",
    "alpine:3.19",
    "ubuntu:22.04",
    "ubuntu:24.04",
    "node:18-alpine",
    "node:20-alpine",
    "python:3.11-slim",
    "python:3.12-slim",
    "golang:1.21-alpine",
    "golang:1.22-alpine",
    "gcr.io/distroless/base",
    "gcr.io/distroless/static",
    "gcr.io/distroless/python3",
    "gcr.io/distroless/nodejs18"
}

# No hardcoded secrets (PO.5.2)
no_secrets if {
    input.security.secrets_scan.found == 0
    not contains_secret_patterns(input.commit.diff)
}

# Check for secret patterns
contains_secret_patterns(text) if {
    patterns := [
        "AKIA[0-9A-Z]{16}",  # AWS Access Key
        "aws_secret_access_key",
        "api[_-]?key",
        "api[_-]?secret",
        "auth[_-]?token",
        "private[_-]?key",
        "password\\s*=\\s*[\"'][^\"']+[\"']",
        "bearer\\s+[a-zA-Z0-9._-]+",
        "[a-f0-9]{40}",  # Generic hash
        "AIza[0-9A-Za-z-_]{35}",  # Google API Key
        "ya29\\.[0-9A-Za-z\\-_]+",  # Google OAuth
        "AAAAB3NzaC1",  # SSH Private Key
        "-----BEGIN RSA PRIVATE KEY-----",
        "-----BEGIN OPENSSH PRIVATE KEY-----"
    ]

    some pattern in patterns
    regex.match(pattern, text)
}

# Build metadata requirements
valid_build_metadata if {
    input.build.id != null
    input.build.timestamp != null
    input.build.builder != null
    input.build.invocation != null
}

# Artifact signing requirements (PS.3.2)
artifacts_signed if {
    every artifact in input.artifacts.outputs {
        artifact.signature != null
        artifact.signature.key_id != null
        artifact.checksum.sha256 != null
    }
}

# Supply chain requirements (PO.3.2)
supply_chain_validated if {
    input.dependencies.verified == true
    input.dependencies.license_check == "passed"
    no_forbidden_licenses
}

# Forbidden licenses check
no_forbidden_licenses if {
    forbidden := {"GPL-3.0", "AGPL-3.0", "LGPL-3.0", "CC-BY-NC"}
    found := {lic | some dep in input.dependencies.list; dep.license in forbidden; lic := dep.license}
    count(found) == 0
}

# Generate violation messages
violations[msg] {
    not signed_commits
    msg := "Build rejected: Commits must be signed"
}

violations[msg] {
    not sbom_generated
    msg := "Build rejected: SBOM generation required in both SPDX and CycloneDX formats"
}

violations[msg] {
    input.security.vulnerabilities.critical > 0
    msg := sprintf("Build rejected: %d critical vulnerabilities found", [input.security.vulnerabilities.critical])
}

violations[msg] {
    count(input.pull_request.approvals) < 2
    msg := sprintf("Build rejected: Requires 2 approvals, found %d", [count(input.pull_request.approvals)])
}

violations[msg] {
    not valid_base_images
    msg := "Build rejected: Using non-approved base images"
}

violations[msg] {
    input.security.secrets_scan.found > 0
    msg := sprintf("Build rejected: %d secrets detected", [input.security.secrets_scan.found])
}

violations[msg] {
    not artifacts_signed
    msg := "Build rejected: All artifacts must be signed"
}

violations[msg] {
    not no_forbidden_licenses
    msg := "Build rejected: Forbidden licenses detected"
}

# Security score calculation
security_score := score if {
    score := sum([
        20 * signed_commits,
        15 * sbom_generated,
        25 * no_critical_cves,
        10 * sufficient_reviewers,
        10 * valid_base_images,
        20 * no_secrets
    ])
}

# Build risk level
risk_level := "LOW" if security_score >= 80
risk_level := "MEDIUM" if {security_score >= 60; security_score < 80}
risk_level := "HIGH" if {security_score >= 40; security_score < 60}
risk_level := "CRITICAL" if security_score < 40

# Policy decision
decision := {
    "allow": allow,
    "violations": violations,
    "security_score": security_score,
    "risk_level": risk_level,
    "timestamp": input.timestamp,
    "build_id": input.build.id
}