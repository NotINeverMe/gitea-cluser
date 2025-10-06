# OPA/Rego policy for CMMC 2.0 Level 2 compliance on GCP
# CMMC Controls: AC, AU, CM, IA, SC, SI
# Author: DevSecOps Platform Team
# Version: 1.0.0

package cmmc.level2.gcp

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Metadata for policy documentation
metadata := {
    "title": "CMMC 2.0 Level 2 GCP Security Policy",
    "description": "Enforces CMMC 2.0 Level 2 security controls for GCP resources",
    "version": "1.0.0",
    "compliance": ["CMMC 2.0 Level 2"],
    "severity_levels": ["CRITICAL", "HIGH", "MEDIUM", "LOW"]
}

# AC.L2-3.1.1: Limit system access to authorized users
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_binding"
    "allUsers" in resource.change.after.members[_]
    msg := sprintf("CMMC AC.L2-3.1.1 VIOLATION: Public access not allowed for IAM binding in %v", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_member"
    contains(resource.change.after.member, "allAuthenticatedUsers")
    msg := sprintf("CMMC AC.L2-3.1.1 VIOLATION: allAuthenticatedUsers access not allowed for %v", [resource.address])
}

# AC.L2-3.1.20: Verify and control external connections
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_firewall"
    "0.0.0.0/0" in resource.change.after.source_ranges[_]
    resource.change.after.direction == "INGRESS"
    not resource.change.after.disabled
    msg := sprintf("CMMC AC.L2-3.1.20 VIOLATION: Unrestricted ingress from 0.0.0.0/0 in firewall %v", [resource.address])
}

# AC.L2-3.1.21: Limit use of portable storage devices
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    disk := resource.change.after.attached_disk[_]
    disk.mode == "READ_WRITE"
    not disk.disk_encryption_key
    msg := sprintf("CMMC AC.L2-3.1.21 VIOLATION: Unencrypted attached disk on instance %v", [resource.address])
}

# AU.L2-3.3.1: Create and retain system audit logs
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project"
    not resource.change.after.labels.audit_logging
    msg := sprintf("CMMC AU.L2-3.3.1 VIOLATION: Audit logging label missing on project %v", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_logging_project_sink"
    not resource.change.after.destination
    msg := sprintf("CMMC AU.L2-3.3.1 VIOLATION: Log sink missing destination for %v", [resource.address])
}

# AU.L2-3.3.2: Ensure audit logs contain required information
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_audit_config"
    log_config := resource.change.after.audit_log_config[_]
    required_log_types := {"ADMIN_READ", "DATA_READ", "DATA_WRITE"}
    provided_types := {t | t := log_config[_].log_type}
    missing := required_log_types - provided_types
    count(missing) > 0
    msg := sprintf("CMMC AU.L2-3.3.2 VIOLATION: Missing audit log types %v in %v", [missing, resource.address])
}

# AU.L2-3.3.8: Protect audit information (log retention)
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_logging_project_bucket_config"
    resource.change.after.retention_days < 90
    msg := sprintf("CMMC AU.L2-3.3.8 VIOLATION: Log retention less than 90 days for %v", [resource.address])
}

# CM.L2-3.4.1: Establish baseline configurations
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    not resource.change.after.labels.baseline_config
    msg := sprintf("CMMC CM.L2-3.4.1 VIOLATION: Missing baseline configuration label on %v", [resource.address])
}

# CM.L2-3.4.2: Enforce security configuration settings
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    not resource.change.after.shielded_instance_config
    msg := sprintf("CMMC CM.L2-3.4.2 VIOLATION: Shielded VM not enabled for %v", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    resource.change.after.shielded_instance_config
    not resource.change.after.shielded_instance_config.enable_secure_boot
    msg := sprintf("CMMC CM.L2-3.4.2 VIOLATION: Secure boot not enabled for %v", [resource.address])
}

# IA.L2-3.5.3: Multifactor authentication
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_binding"
    role_requires_mfa(resource.change.after.role)
    not has_mfa_condition(resource.change.after.condition)
    msg := sprintf("CMMC IA.L2-3.5.3 VIOLATION: MFA required for privileged role %v in %v", [resource.change.after.role, resource.address])
}

# Helper function to check roles requiring MFA
role_requires_mfa(role) {
    privileged_roles := {
        "roles/owner",
        "roles/editor",
        "roles/iam.securityAdmin",
        "roles/compute.admin",
        "roles/storage.admin"
    }
    role in privileged_roles
}

# Helper function to check for MFA condition
has_mfa_condition(condition) {
    condition
    contains(condition.expression, "request.auth.claims")
    contains(condition.expression, "mfa")
}

# SC.L2-3.13.8: Implement cryptographic mechanisms (encryption at rest)
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_disk"
    not resource.change.after.disk_encryption_key
    msg := sprintf("CMMC SC.L2-3.13.8 VIOLATION: Disk encryption not configured for %v", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_storage_bucket"
    not resource.change.after.encryption
    msg := sprintf("CMMC SC.L2-3.13.8 VIOLATION: Bucket encryption not configured for %v", [resource.address])
}

# SC.L2-3.13.11: Employ FIPS-validated cryptography
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_kms_crypto_key"
    resource.change.after.purpose != "ENCRYPT_DECRYPT"
    msg := sprintf("CMMC SC.L2-3.13.11 VIOLATION: KMS key purpose must be ENCRYPT_DECRYPT for %v", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_kms_crypto_key"
    algorithm := resource.change.after.version_template.algorithm
    not algorithm in allowed_algorithms
    msg := sprintf("CMMC SC.L2-3.13.11 VIOLATION: Non-FIPS algorithm %v used in %v", [algorithm, resource.address])
}

# FIPS-approved algorithms for GCP KMS
allowed_algorithms := {
    "GOOGLE_SYMMETRIC_ENCRYPTION",
    "RSA_SIGN_PSS_2048_SHA256",
    "RSA_SIGN_PSS_3072_SHA256",
    "RSA_SIGN_PSS_4096_SHA256",
    "RSA_SIGN_PSS_4096_SHA512",
    "EC_SIGN_P256_SHA256",
    "EC_SIGN_P384_SHA384"
}

# SC.L2-3.13.6: Deny network communications traffic by default
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_firewall"
    resource.change.after.direction == "INGRESS"
    count(resource.change.after.deny) == 0
    not resource.change.after.priority
    msg := sprintf("CMMC SC.L2-3.13.6 VIOLATION: Default deny rule missing for ingress in %v", [resource.address])
}

# SI.L2-3.14.2: Provide protection from malicious code
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    not resource.change.after.metadata["enable-guest-attributes"]
    msg := sprintf("CMMC SI.L2-3.14.2 WARNING: Guest attributes should be disabled for security in %v", [resource.address])
}

# SI.L2-3.14.3: Monitor security alerts and advisories
warn[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project"
    not resource.change.after.labels.security_contact
    msg := sprintf("CMMC SI.L2-3.14.3 WARNING: Security contact label missing on project %v", [resource.address])
}

# Aggregated compliance score
compliance_score := score {
    total_resources := count(input.resource_changes)
    violations := count(deny)
    warnings := count(warn)
    score := ((total_resources - violations) / total_resources) * 100
}

# Summary report generation
summary := report {
    report := {
        "compliance_framework": "CMMC 2.0 Level 2",
        "scan_timestamp": time.now_ns(),
        "total_resources": count(input.resource_changes),
        "violations": count(deny),
        "warnings": count(warn),
        "compliance_score": compliance_score,
        "critical_findings": [msg | deny[msg]],
        "warning_findings": [msg | warn[msg]]
    }
}