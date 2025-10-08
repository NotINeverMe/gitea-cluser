package security.scanning

import future.keywords.contains
import future.keywords.if
import future.keywords.in

default allow := false

# Security Scanning Policy for SSDF Compliance
# Enforces security thresholds and code quality requirements

# Main allow rule - all security criteria must pass
allow if {
    no_hardcoded_secrets
    meets_coverage_requirements
    within_sast_thresholds
    dependency_compliance
    container_security
    infrastructure_compliance
    within_dead_code_thresholds
}

# No hardcoded secrets (PO.5.2, PS.1.1)
no_hardcoded_secrets if {
    count(detected_secrets) == 0
}

# Detect secrets using patterns
detected_secrets[secret] {
    secret_patterns := [
        # AWS
        "AKIA[0-9A-Z]{16}",
        "aws[_\\s]?secret[_\\s]?access[_\\s]?key[\"'\\s]*[=:][\"'\\s]*[A-Za-z0-9/+=]{40}",

        # Azure
        "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",

        # GCP
        "AIza[0-9A-Za-z-_]{35}",
        "\"private_key\"\\s*:\\s*\"-----BEGIN RSA PRIVATE KEY-----",

        # GitHub
        "ghp_[a-zA-Z0-9]{36}",
        "gho_[a-zA-Z0-9]{36}",
        "ghs_[a-zA-Z0-9]{36}",
        "ghu_[a-zA-Z0-9]{36}",

        # Generic API Keys
        "api[_\\-\\s]?key[\"'\\s]*[=:][\"'\\s]*[A-Za-z0-9\\-_]{20,}",
        "api[_\\-\\s]?secret[\"'\\s]*[=:][\"'\\s]*[A-Za-z0-9\\-_]{20,}",
        "token[\"'\\s]*[=:][\"'\\s]*[A-Za-z0-9\\-_.]{20,}",

        # Private Keys
        "-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----",
        "-----BEGIN PGP PRIVATE KEY BLOCK-----",

        # Database URLs
        "(postgres|mysql|mongodb)://[^:]+:[^@]+@[^/]+",

        # JWT
        "eyJ[A-Za-z0-9-_=]+\\.[A-Za-z0-9-_=]+\\.[A-Za-z0-9-_=]+"
    ]

    some file in input.files
    some pattern in secret_patterns
    regex.match(pattern, file.content)
    secret := {
        "file": file.path,
        "pattern": pattern,
        "line": file.line
    }
}

# Code coverage requirements (PW.6.1)
meets_coverage_requirements if {
    input.coverage.percentage >= minimum_coverage_threshold
}

minimum_coverage_threshold := 80

# Dead code detection thresholds (PW.6.1 - Code Review, PW.7.1 - Testing)
within_dead_code_thresholds if {
    python_dead_code_acceptable
    javascript_dead_code_acceptable
    shell_dead_code_acceptable
    total_dead_code_acceptable
}

python_dead_code_acceptable if {
    input.dead_code.python.total <= 20
}

javascript_dead_code_acceptable if {
    input.dead_code.javascript.total <= 10
}

shell_dead_code_acceptable if {
    input.dead_code.shell.total <= 15
}

total_dead_code_acceptable if {
    total_dead_code := input.dead_code.python.total +
                       input.dead_code.javascript.total +
                       input.dead_code.shell.total
    total_dead_code <= 50
}

# SAST finding thresholds (PW.7.1, PW.7.2)
within_sast_thresholds if {
    input.sast.findings.critical == 0
    input.sast.findings.high < 5
    input.sast.findings.medium < 20
}

# Enhanced SAST rules for specific vulnerabilities
no_sql_injection if {
    sql_injection_patterns := [
        "SELECT .* FROM .* WHERE .* = .*\\$",
        "INSERT INTO .* VALUES.*\\$",
        "UPDATE .* SET .* = .*\\$",
        "DELETE FROM .* WHERE .* = .*\\$"
    ]

    not any_pattern_matches(input.files, sql_injection_patterns)
}

no_xss_vulnerabilities if {
    xss_patterns := [
        "innerHTML\\s*=",
        "document\\.write\\(",
        "eval\\(",
        "setTimeout\\([^,]+,",
        "setInterval\\([^,]+,",
        "Function\\([\"'][^\"']+[\"']\\)"
    ]

    not any_pattern_matches(input.files, xss_patterns)
}

any_pattern_matches(files, patterns) if {
    some file in files
    some pattern in patterns
    regex.match(pattern, file.content)
}

# Dependency license compliance (PW.3.1)
dependency_compliance if {
    no_forbidden_licenses
    no_vulnerable_dependencies
    all_dependencies_declared
}

no_forbidden_licenses if {
    forbidden_licenses := {
        "GPL-3.0",
        "GPL-3.0-only",
        "GPL-3.0-or-later",
        "AGPL-3.0",
        "AGPL-3.0-only",
        "AGPL-3.0-or-later",
        "LGPL-3.0",
        "LGPL-3.0-only",
        "LGPL-3.0-or-later",
        "CC-BY-NC",
        "CC-BY-NC-SA",
        "CC-BY-NC-ND",
        "SSPL-1.0",
        "Commons-Clause"
    }

    found_forbidden := {dep.name |
        some dep in input.dependencies
        dep.license in forbidden_licenses
    }

    count(found_forbidden) == 0
}

no_vulnerable_dependencies if {
    vulnerable := {dep.name |
        some dep in input.dependencies
        dep.vulnerabilities.critical > 0
    }

    count(vulnerable) == 0
}

all_dependencies_declared if {
    input.dependencies.undeclared == 0
    input.dependencies.phantom == 0
}

# Container security requirements (PW.7.1, PS.3.1)
container_security if {
    container_uses_non_root_user
    container_readonly_filesystem
    container_no_privileged
    container_resource_limits
    container_health_checks
}

container_uses_non_root_user if {
    input.container.user != "root"
    input.container.user != "0"
}

container_readonly_filesystem if {
    input.container.readonly_root == true
}

container_no_privileged if {
    input.container.privileged == false
    input.container.capabilities.drop == ["ALL"]
}

container_resource_limits if {
    input.container.resources.limits.memory != null
    input.container.resources.limits.cpu != null
}

container_health_checks if {
    input.container.healthcheck != null
    input.container.healthcheck.test != null
}

# Infrastructure as Code compliance (PW.4.2)
infrastructure_compliance if {
    terraform_security_checks
    kubernetes_security_checks
    cloud_security_checks
}

terraform_security_checks if {
    input.iac.terraform.encrypted_storage == true
    input.iac.terraform.versioned_modules == true
    input.iac.terraform.security_groups_restricted == true
}

kubernetes_security_checks if {
    input.iac.kubernetes.network_policies == true
    input.iac.kubernetes.pod_security_policies == true
    input.iac.kubernetes.rbac_enabled == true
}

cloud_security_checks if {
    input.iac.cloud.encryption_at_rest == true
    input.iac.cloud.encryption_in_transit == true
    input.iac.cloud.least_privilege_iam == true
    input.iac.cloud.audit_logging == true
}

# Generate violation messages
violations[msg] {
    count(detected_secrets) > 0
    msg := sprintf("Security rejected: %d secrets detected", [count(detected_secrets)])
}

violations[msg] {
    not meets_coverage_requirements
    msg := sprintf("Security rejected: Code coverage %.1f%% below minimum %d%%",
        [input.coverage.percentage, minimum_coverage_threshold])
}

violations[msg] {
    input.sast.findings.critical > 0
    msg := sprintf("Security rejected: %d critical SAST findings", [input.sast.findings.critical])
}

violations[msg] {
    input.sast.findings.high >= 5
    msg := sprintf("Security rejected: %d high severity findings (max 4)", [input.sast.findings.high])
}

violations[msg] {
    input.sast.findings.medium >= 20
    msg := sprintf("Security rejected: %d medium severity findings (max 19)", [input.sast.findings.medium])
}

violations[msg] {
    not no_forbidden_licenses
    forbidden := {dep.name |
        some dep in input.dependencies
        dep.license in forbidden_licenses
    }
    msg := sprintf("Security rejected: Forbidden licenses in: %v", [forbidden])
}

violations[msg] {
    not no_vulnerable_dependencies
    vulnerable := {dep.name |
        some dep in input.dependencies
        dep.vulnerabilities.critical > 0
    }
    msg := sprintf("Security rejected: Critical vulnerabilities in: %v", [vulnerable])
}

violations[msg] {
    not container_uses_non_root_user
    msg := "Security rejected: Container must run as non-root user"
}

violations[msg] {
    not container_readonly_filesystem
    msg := "Security rejected: Container must use readonly root filesystem"
}

violations[msg] {
    not container_no_privileged
    msg := "Security rejected: Container must not run in privileged mode"
}

violations[msg] {
    not python_dead_code_acceptable
    msg := sprintf("Security rejected: Python dead code (%d) exceeds threshold (20)",
        [input.dead_code.python.total])
}

violations[msg] {
    not javascript_dead_code_acceptable
    msg := sprintf("Security rejected: JavaScript dead code (%d) exceeds threshold (10)",
        [input.dead_code.javascript.total])
}

violations[msg] {
    not shell_dead_code_acceptable
    msg := sprintf("Security rejected: Shell dead code (%d) exceeds threshold (15)",
        [input.dead_code.shell.total])
}

violations[msg] {
    not total_dead_code_acceptable
    total_dead_code := input.dead_code.python.total +
                       input.dead_code.javascript.total +
                       input.dead_code.shell.total
    msg := sprintf("Security rejected: Total dead code (%d) exceeds threshold (50)",
        [total_dead_code])
}

# Security score calculation (updated to include dead code - total = 100)
security_score := score if {
    score := sum([
        15 * no_hardcoded_secrets,
        10 * meets_coverage_requirements,
        20 * within_sast_thresholds,
        15 * dependency_compliance,
        15 * container_security,
        15 * infrastructure_compliance,
        10 * within_dead_code_thresholds
    ])
}

# Risk assessment
risk_level := "LOW" if security_score >= 90
risk_level := "MEDIUM" if {security_score >= 70; security_score < 90}
risk_level := "HIGH" if {security_score >= 50; security_score < 70}
risk_level := "CRITICAL" if security_score < 50

# Recommended actions
recommendations[action] {
    count(detected_secrets) > 0
    action := "Remove hardcoded secrets and use secret management service"
}

recommendations[action] {
    input.coverage.percentage < minimum_coverage_threshold
    action := sprintf("Increase test coverage to %d%%", [minimum_coverage_threshold])
}

recommendations[action] {
    input.sast.findings.high >= 3
    action := "Address high severity SAST findings before deployment"
}

recommendations[action] {
    not container_uses_non_root_user
    action := "Configure container to run as non-root user"
}

recommendations[action] {
    input.dead_code.python.total > 10
    action := sprintf("Refactor Python code to remove %d dead code instances (Vulture/PyLint)",
        [input.dead_code.python.total])
}

recommendations[action] {
    input.dead_code.javascript.total > 5
    action := sprintf("Clean up JavaScript code: remove %d unused variables/dependencies (ESLint/depcheck)",
        [input.dead_code.javascript.total])
}

recommendations[action] {
    input.dead_code.shell.total > 8
    action := sprintf("Fix shell scripts: remove %d unused variables/unreachable code (ShellCheck)",
        [input.dead_code.shell.total])
}

# Policy decision
decision := {
    "allow": allow,
    "violations": violations,
    "security_score": security_score,
    "risk_level": risk_level,
    "recommendations": recommendations,
    "timestamp": input.timestamp,
    "scan_id": input.scan_id
}