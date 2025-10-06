# OPA Policies for CMMC 2.0 and NIST SP 800-171 Compliance
# Terraform Infrastructure Validation

package terraform.cmmc

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# CMMC 2.0: CM.L2-3.4.2 - Establish baseline configurations
# NIST SP 800-171: 3.4.2

# Deny unencrypted storage
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_storage_bucket"
    encryption := resource.change.after.encryption[_]
    not encryption.default_kms_key_name
    msg := sprintf("CMMC CM.L2-3.4.2: Storage bucket '%s' must use customer-managed encryption (CMEK)", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_disk"
    not resource.change.after.disk_encryption_key
    msg := sprintf("CMMC CM.L2-3.4.2: Compute disk '%s' must use encryption", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_sql_database_instance"
    settings := resource.change.after.settings[_]
    not settings.disk_encryption_configuration
    msg := sprintf("CMMC CM.L2-3.4.2: SQL instance '%s' must use disk encryption", [resource.address])
}

# CMMC 2.0: CM.L2-3.4.3 - Track security configuration changes
# NIST SP 800-171: 3.4.3

# Require audit logging
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project"
    not resource.change.after.audit_log_config
    msg := sprintf("CMMC CM.L2-3.4.3: Project '%s' must have audit logging enabled", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_storage_bucket"
    not resource.change.after.logging
    msg := sprintf("CMMC CM.L2-3.4.3: Storage bucket '%s' must have access logging enabled", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    metadata := resource.change.after.metadata
    not metadata.enable_oslogin
    msg := sprintf("CMMC CM.L2-3.4.3: Compute instance '%s' must have OS Login enabled for audit", [resource.address])
}

# CMMC 2.0: CM.L2-3.4.9 - Configure systems to provide only essential capabilities
# NIST SP 800-171: 3.4.9

# Deny overly permissive IAM roles
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_member"
    resource.change.after.role == "roles/owner"
    msg := sprintf("CMMC CM.L2-3.4.9: IAM binding '%s' uses Owner role - use least privilege", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_member"
    resource.change.after.role == "roles/editor"
    msg := sprintf("CMMC CM.L2-3.4.9: IAM binding '%s' uses Editor role - consider more restrictive roles", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_binding"
    contains(resource.change.after.members[_], "allUsers")
    msg := sprintf("CMMC CM.L2-3.4.9: IAM binding '%s' grants access to allUsers - restrict access", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_project_iam_binding"
    contains(resource.change.after.members[_], "allAuthenticatedUsers")
    msg := sprintf("CMMC CM.L2-3.4.9: IAM binding '%s' grants access to allAuthenticatedUsers - restrict access", [resource.address])
}

# Network security - deny public IPs on sensitive resources
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    network := resource.change.after.network_interface[_]
    network.access_config
    resource.change.after.labels.environment == "production"
    msg := sprintf("CMMC CM.L2-3.4.9: Production instance '%s' has public IP - use private IPs only", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_sql_database_instance"
    settings := resource.change.after.settings[_]
    ip_config := settings.ip_configuration[_]
    ip_config.ipv4_enabled
    not ip_config.require_ssl
    msg := sprintf("CMMC CM.L2-3.4.9: SQL instance '%s' with public IP must require SSL", [resource.address])
}

# Firewall rules - deny overly permissive rules
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_firewall"
    resource.change.after.source_ranges[_] == "0.0.0.0/0"
    contains(resource.change.after.allowed[_].ports[_], "22")
    msg := sprintf("CMMC CM.L2-3.4.9: Firewall rule '%s' allows SSH from 0.0.0.0/0 - restrict source IPs", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_firewall"
    resource.change.after.source_ranges[_] == "0.0.0.0/0"
    contains(resource.change.after.allowed[_].ports[_], "3389")
    msg := sprintf("CMMC CM.L2-3.4.9: Firewall rule '%s' allows RDP from 0.0.0.0/0 - restrict source IPs", [resource.address])
}

# VPC Service Controls for CUI data
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_storage_bucket"
    resource.change.after.labels.data_classification == "cui"
    not resource.change.after.uniform_bucket_level_access
    msg := sprintf("NIST SP 800-171: Storage bucket '%s' containing CUI must use uniform access", [resource.address])
}

# Binary Authorization for GKE
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not resource.change.after.binary_authorization
    msg := sprintf("CMMC CM.L2-3.4.2: GKE cluster '%s' must have Binary Authorization enabled", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    binary_auth := resource.change.after.binary_authorization[_]
    not binary_auth.enabled
    msg := sprintf("CMMC CM.L2-3.4.2: GKE cluster '%s' must have Binary Authorization enabled", [resource.address])
}

# Backup requirements
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_sql_database_instance"
    settings := resource.change.after.settings[_]
    backup := settings.backup_configuration[_]
    not backup.enabled
    msg := sprintf("CMMC CM.L2-3.4.2: SQL instance '%s' must have automated backups enabled", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_sql_database_instance"
    settings := resource.change.after.settings[_]
    backup := settings.backup_configuration[_]
    backup.point_in_time_recovery_enabled != true
    msg := sprintf("CMMC CM.L2-3.4.2: SQL instance '%s' must have point-in-time recovery enabled", [resource.address])
}

# Monitoring requirements
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_instance"
    not resource.change.after.labels.monitoring
    msg := sprintf("NIST SP 800-171 3.4.3: Instance '%s' must have monitoring label defined", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_storage_bucket"
    not resource.change.after.lifecycle_rule
    resource.change.after.labels.data_classification == "cui"
    msg := sprintf("NIST SP 800-171: CUI bucket '%s' must have lifecycle rules defined", [resource.address])
}

# Production-specific rules
package terraform.production

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Stricter rules for production
deny[msg] {
    resource := input.resource_changes[_]
    resource.change.after.labels.environment == "production"
    resource.type == "google_compute_instance"
    not resource.change.after.deletion_protection
    msg := sprintf("Production instance '%s' must have deletion protection enabled", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.change.after.labels.environment == "production"
    resource.type == "google_sql_database_instance"
    not resource.change.after.deletion_protection
    msg := sprintf("Production SQL instance '%s' must have deletion protection enabled", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.change.after.labels.environment == "production"
    resource.type == "google_container_cluster"
    not resource.change.after.private_cluster_config
    msg := sprintf("Production GKE cluster '%s' must be private", [resource.address])
}

# High availability requirements for production
deny[msg] {
    resource := input.resource_changes[_]
    resource.change.after.labels.environment == "production"
    resource.type == "google_sql_database_instance"
    settings := resource.change.after.settings[_]
    not settings.availability_type == "REGIONAL"
    msg := sprintf("Production SQL instance '%s' must be configured for high availability (REGIONAL)", [resource.address])
}

# Maintenance windows for production
warn[msg] {
    resource := input.resource_changes[_]
    resource.change.after.labels.environment == "production"
    resource.type == "google_sql_database_instance"
    settings := resource.change.after.settings[_]
    not settings.maintenance_window
    msg := sprintf("Production SQL instance '%s' should have maintenance window configured", [resource.address])
}

warn[msg] {
    resource := input.resource_changes[_]
    resource.change.after.labels.environment == "production"
    resource.type == "google_container_cluster"
    not resource.change.after.maintenance_policy
    msg := sprintf("Production GKE cluster '%s' should have maintenance policy configured", [resource.address])
}