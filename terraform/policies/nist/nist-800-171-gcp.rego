# OPA/Rego policy for NIST SP 800-171 Rev. 2 compliance on GCP
# Focus on CUI (Controlled Unclassified Information) protection
# Author: DevSecOps Platform Team
# Version: 1.0.0

package nist.sp800171.gcp

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Metadata
metadata := {
    "title": "NIST SP 800-171 Rev. 2 GCP Security Policy",
    "description": "Enforces NIST SP 800-171 Rev. 2 security requirements for protecting CUI in GCP",
    "version": "1.0.0",
    "compliance": ["NIST SP 800-171 Rev. 2"],
    "last_updated": "2024-01-01"
}

# 3.1.1 - Limit system access to authorized users
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    not resource.change.after.metadata["enable-oslogin"]
    msg := sprintf("NIST 3.1.1 VIOLATION: OS Login must be enabled for access control on %v", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type in ["google_project_iam_binding", "google_project_iam_member"]
    has_public_member(resource.change.after)
    msg := sprintf("NIST 3.1.1 VIOLATION: Public access not allowed in IAM configuration %v", [resource.address])
}

has_public_member(iam_config) {
    "allUsers" in iam_config.members[_]
}

has_public_member(iam_config) {
    contains(iam_config.member, "allUsers")
}

# 3.1.2 - Limit system access to authorized transactions and functions
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_binding"
    overly_permissive_role(resource.change.after.role)
    msg := sprintf("NIST 3.1.2 VIOLATION: Overly permissive role %v assigned in %v", [resource.change.after.role, resource.address])
}

overly_permissive_role(role) {
    role in ["roles/owner", "roles/editor"]
}

# 3.1.12 - Monitor and control remote access sessions
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    has_public_ip(resource.change.after)
    not has_iap_tag(resource.change.after)
    msg := sprintf("NIST 3.1.12 VIOLATION: Instance %v has public IP without IAP protection", [resource.address])
}

has_public_ip(instance) {
    instance.network_interface[_].access_config
}

has_iap_tag(instance) {
    instance.tags[_] == "iap-protected"
}

# 3.1.20 - Verify and control connections to external systems
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_firewall"
    resource.change.after.direction == "EGRESS"
    "0.0.0.0/0" in resource.change.after.destination_ranges[_]
    not has_egress_justification(resource.change.after)
    msg := sprintf("NIST 3.1.20 VIOLATION: Unrestricted egress to 0.0.0.0/0 in %v", [resource.address])
}

has_egress_justification(firewall) {
    firewall.description
    contains(firewall.description, "APPROVED:")
}

# 3.3.1 - Create and retain audit records
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_storage_bucket"
    is_log_bucket(resource.change.after)
    not has_retention_policy(resource.change.after)
    msg := sprintf("NIST 3.3.1 VIOLATION: Log bucket %v missing retention policy", [resource.address])
}

is_log_bucket(bucket) {
    contains(bucket.name, "log")
}

has_retention_policy(bucket) {
    bucket.retention_policy
    bucket.retention_policy.retention_period >= 7776000  # 90 days in seconds
}

# 3.3.2 - Ensure audit records contain required information
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_logging_metric"
    not contains_required_labels(resource.change.after)
    msg := sprintf("NIST 3.3.2 VIOLATION: Logging metric %v missing required labels", [resource.address])
}

contains_required_labels(metric) {
    required := {"severity", "resource_type", "user_identity"}
    provided := {k | metric.label_extractors[k]}
    missing := required - provided
    count(missing) == 0
}

# 3.4.1 - Establish baseline configurations
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance_template"
    not has_baseline_metadata(resource.change.after)
    msg := sprintf("NIST 3.4.1 VIOLATION: Instance template %v missing baseline configuration metadata", [resource.address])
}

has_baseline_metadata(template) {
    template.metadata.baseline_version
    template.metadata.baseline_date
}

# 3.4.2 - Establish and enforce security configuration settings
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    not resource.change.after.deletion_protection
    msg := sprintf("NIST 3.4.2 VIOLATION: Deletion protection must be enabled for %v", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_sql_database_instance"
    resource.change.after.settings.ip_configuration.ipv4_enabled
    msg := sprintf("NIST 3.4.2 VIOLATION: Public IP should be disabled for Cloud SQL %v", [resource.address])
}

# 3.5.1 - Identify system users
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_service_account"
    not has_description(resource.change.after)
    msg := sprintf("NIST 3.5.1 VIOLATION: Service account %v missing description", [resource.address])
}

has_description(service_account) {
    service_account.description
    count(service_account.description) > 10
}

# 3.5.3 - Use multifactor authentication
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_binding"
    is_privileged_role(resource.change.after.role)
    not has_mfa_condition(resource.change.after)
    msg := sprintf("NIST 3.5.3 VIOLATION: MFA required for privileged role %v in %v", [resource.change.after.role, resource.address])
}

is_privileged_role(role) {
    privileged := {
        "roles/owner",
        "roles/editor",
        "roles/iam.securityAdmin",
        "roles/iam.serviceAccountAdmin",
        "roles/compute.admin",
        "roles/storage.admin"
    }
    role in privileged
}

has_mfa_condition(binding) {
    binding.condition
    contains(binding.condition.expression, "has({}.multifactor)")
}

# 3.8.1 - Protect CUI on system media
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_disk"
    not has_encryption(resource.change.after)
    msg := sprintf("NIST 3.8.1 VIOLATION: Disk encryption required for %v", [resource.address])
}

has_encryption(disk) {
    disk.disk_encryption_key.kms_key_self_link
}

# 3.8.9 - Protect CUI during transport
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_storage_bucket"
    not has_uniform_access(resource.change.after)
    msg := sprintf("NIST 3.8.9 WARNING: Uniform bucket-level access recommended for %v", [resource.address])
}

has_uniform_access(bucket) {
    bucket.uniform_bucket_level_access.enabled
}

# 3.11.2 - Scan for vulnerabilities periodically
warn[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not has_vulnerability_scanning(resource.change.after)
    msg := sprintf("NIST 3.11.2 WARNING: Enable vulnerability scanning for GKE cluster %v", [resource.address])
}

has_vulnerability_scanning(cluster) {
    cluster.enable_binary_authorization
}

# 3.13.1 - Monitor and control remote access
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_firewall"
    allows_ssh_from_internet(resource.change.after)
    msg := sprintf("NIST 3.13.1 VIOLATION: SSH from internet not allowed in %v", [resource.address])
}

allows_ssh_from_internet(firewall) {
    firewall.direction == "INGRESS"
    "0.0.0.0/0" in firewall.source_ranges[_]
    rule := firewall.allow[_]
    "22" in rule.ports[_]
}

# 3.13.2 - Employ cryptographic mechanisms for confidentiality
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_pubsub_topic"
    not has_kms_encryption(resource.change.after)
    msg := sprintf("NIST 3.13.2 VIOLATION: KMS encryption required for Pub/Sub topic %v", [resource.address])
}

has_kms_encryption(topic) {
    topic.kms_key_name
}

# 3.13.5 - Implement cryptographic key management
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_kms_crypto_key"
    not has_rotation_period(resource.change.after)
    msg := sprintf("NIST 3.13.5 VIOLATION: Key rotation period required for %v", [resource.address])
}

has_rotation_period(key) {
    key.rotation_period
    # Rotation period should be <= 90 days (7776000 seconds)
    to_number(regex.split("s", key.rotation_period)[0]) <= 7776000
}

# 3.13.11 - Employ FIPS-validated cryptography
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_kms_crypto_key"
    not is_fips_compliant_algorithm(resource.change.after)
    msg := sprintf("NIST 3.13.11 VIOLATION: FIPS-validated algorithm required for %v", [resource.address])
}

is_fips_compliant_algorithm(key) {
    fips_algorithms := {
        "GOOGLE_SYMMETRIC_ENCRYPTION",
        "RSA_SIGN_PSS_2048_SHA256",
        "RSA_SIGN_PSS_3072_SHA256",
        "RSA_SIGN_PSS_4096_SHA256",
        "RSA_SIGN_PSS_4096_SHA512",
        "RSA_DECRYPT_OAEP_2048_SHA256",
        "RSA_DECRYPT_OAEP_3072_SHA256",
        "RSA_DECRYPT_OAEP_4096_SHA256",
        "RSA_DECRYPT_OAEP_4096_SHA512",
        "EC_SIGN_P256_SHA256",
        "EC_SIGN_P384_SHA384"
    }
    key.version_template.algorithm in fips_algorithms
}

# 3.14.1 - Identify and manage system flaws
warn[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not has_auto_upgrade(resource.change.after)
    msg := sprintf("NIST 3.14.1 WARNING: Enable auto-upgrade for GKE cluster %v", [resource.address])
}

has_auto_upgrade(cluster) {
    cluster.node_config.management.auto_upgrade
}

# 3.14.2 - Provide protection from malicious code
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    has_startup_script(resource.change.after)
    not has_script_validation(resource.change.after)
    msg := sprintf("NIST 3.14.2 WARNING: Startup script requires validation in %v", [resource.address])
}

has_startup_script(instance) {
    instance.metadata.startup-script
}

has_script_validation(instance) {
    instance.metadata.startup-script-hash
}

# 3.14.3 - Monitor system security alerts
warn[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project"
    not has_security_command_center(resource.change.after)
    msg := sprintf("NIST 3.14.3 WARNING: Enable Security Command Center for project %v", [resource.address])
}

has_security_command_center(project) {
    project.labels.scc_enabled == "true"
}

# Compliance scoring
compliance_score := score {
    total_checks := count(deny) + count(warn)
    passed_checks := count(input.resource_changes) - total_checks
    score := (passed_checks / count(input.resource_changes)) * 100
}

# Executive summary generation
executive_summary := summary {
    summary := {
        "compliance_framework": "NIST SP 800-171 Rev. 2",
        "scan_date": time.now_ns(),
        "total_resources": count(input.resource_changes),
        "critical_violations": count(deny),
        "warnings": count(warn),
        "compliance_percentage": compliance_score,
        "requires_immediate_action": count(deny) > 0,
        "top_violations": array.slice(array.sort([msg | deny[msg]]), 0, 5)
    }
}