# Output Values for Gitea GCP Deployment
# CMMC 2.0 Level 2 Compliant Infrastructure

# ============================================================================
# INSTANCE INFORMATION
# ============================================================================

output "instance_name" {
  description = "Name of the Gitea Compute Engine instance"
  value       = google_compute_instance.gitea_server.name
}

output "instance_id" {
  description = "Instance ID of the Gitea server"
  value       = google_compute_instance.gitea_server.instance_id
}

output "instance_external_ip" {
  description = "External IP address of the Gitea instance"
  value       = google_compute_address.gitea_ip.address
}

output "instance_internal_ip" {
  description = "Internal IP address of the Gitea instance"
  value       = google_compute_instance.gitea_server.network_interface[0].network_ip
}

output "instance_self_link" {
  description = "Self link of the Gitea instance"
  value       = google_compute_instance.gitea_server.self_link
}

output "instance_zone" {
  description = "Zone where the instance is deployed"
  value       = google_compute_instance.gitea_server.zone
}

# ============================================================================
# ACCESS INFORMATION
# ============================================================================

output "gitea_url" {
  description = "URL to access Gitea web interface"
  value       = "https://${var.gitea_domain}"
}

output "gitea_api_url" {
  description = "URL for Gitea API access"
  value       = "https://${var.gitea_domain}/api/v1"
}

output "git_ssh_url" {
  description = "Git SSH URL format for repositories"
  value       = length(var.allowed_git_ssh_cidr_ranges) > 0 ? "git@${var.gitea_domain}:10001" : "Git SSH is disabled (no allowed CIDR ranges)"
}

output "ssh_command" {
  description = "SSH command to connect to the instance via IAP"
  value = var.enable_iap ? format(
    "gcloud compute ssh --zone=%s %s --project=%s --tunnel-through-iap",
    var.zone,
    google_compute_instance.gitea_server.name,
    var.project_id
  ) : "IAP is disabled. Use: ssh user@${google_compute_address.gitea_ip.address}"
}

output "ssh_tunnel_command" {
  description = "Command to create SSH tunnel for local access via IAP"
  value = var.enable_iap ? format(
    "gcloud compute ssh --zone=%s %s --project=%s --tunnel-through-iap -- -L 8080:localhost:443 -N",
    var.zone,
    google_compute_instance.gitea_server.name,
    var.project_id
  ) : "IAP is disabled"
}

# ============================================================================
# STORAGE BUCKETS
# ============================================================================

output "evidence_bucket_name" {
  description = "Name of the evidence storage bucket"
  value       = google_storage_bucket.evidence.name
}

output "evidence_bucket_url" {
  description = "URL of the evidence storage bucket"
  value       = google_storage_bucket.evidence.url
}

output "backup_bucket_name" {
  description = "Name of the backup storage bucket"
  value       = google_storage_bucket.backup.name
}

output "backup_bucket_url" {
  description = "URL of the backup storage bucket"
  value       = google_storage_bucket.backup.url
}

output "logs_bucket_name" {
  description = "Name of the logs storage bucket"
  value       = google_storage_bucket.logs.name
}

output "logs_bucket_url" {
  description = "URL of the logs storage bucket"
  value       = google_storage_bucket.logs.url
}

output "dr_backup_bucket_name" {
  description = "Name of the disaster recovery backup bucket (if enabled)"
  value       = var.enable_cross_region_backup ? google_storage_bucket.backup_dr[0].name : "Not enabled"
}

# ============================================================================
# SERVICE ACCOUNTS
# ============================================================================

output "gitea_service_account_email" {
  description = "Email of the Gitea service account"
  value       = google_service_account.gitea_sa.email
}

output "gitea_service_account_id" {
  description = "ID of the Gitea service account"
  value       = google_service_account.gitea_sa.id
}

output "evidence_service_account_email" {
  description = "Email of the evidence collection service account"
  value       = google_service_account.evidence_sa.email
}

output "backup_service_account_email" {
  description = "Email of the backup service account"
  value       = google_service_account.backup_sa.email
}

# ============================================================================
# NETWORK INFORMATION
# ============================================================================

output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.gitea_network.name
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.gitea_network.self_link
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.gitea_subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.gitea_subnet.ip_cidr_range
}

output "subnet_self_link" {
  description = "Self link of the subnet"
  value       = google_compute_subnetwork.gitea_subnet.self_link
}

output "cloud_nat_enabled" {
  description = "Whether Cloud NAT is enabled"
  value       = var.enable_cloud_nat
}

# ============================================================================
# SECURITY RESOURCES
# ============================================================================

output "kms_keyring_name" {
  description = "Name of the KMS keyring (if enabled)"
  value       = var.enable_kms ? google_kms_key_ring.gitea_keyring[0].name : "KMS not enabled"
}

output "kms_disk_key_id" {
  description = "ID of the KMS key for disk encryption (if enabled)"
  value       = var.enable_kms ? google_kms_crypto_key.disk_key[0].id : "KMS not enabled"
}

output "kms_storage_key_id" {
  description = "ID of the KMS key for storage encryption (if enabled)"
  value       = var.enable_kms ? google_kms_crypto_key.storage_key[0].id : "KMS not enabled"
}

output "cloud_armor_policy_name" {
  description = "Name of the Cloud Armor WAF policy (if enabled)"
  value       = var.enable_cloud_armor ? google_compute_security_policy.gitea_waf[0].name : "Cloud Armor not enabled"
}

output "secret_manager_enabled" {
  description = "Whether Secret Manager is enabled"
  value       = var.enable_secret_manager
}

output "admin_password_secret_name" {
  description = "Name of the admin password secret (if Secret Manager is enabled)"
  value       = var.enable_secret_manager ? google_secret_manager_secret.admin_password[0].secret_id : "Secret Manager not enabled"
}

output "db_password_secret_name" {
  description = "Name of the database password secret (if Secret Manager is enabled)"
  value       = var.enable_secret_manager ? google_secret_manager_secret.db_password[0].secret_id : "Secret Manager not enabled"
}

# ============================================================================
# MONITORING & ALERTING
# ============================================================================

output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "uptime_check_id" {
  description = "ID of the HTTPS uptime check (if enabled)"
  value       = var.enable_uptime_checks ? google_monitoring_uptime_check_config.gitea_https[0].uptime_check_id : "Uptime checks not enabled"
}

output "dashboard_url" {
  description = "URL to the monitoring dashboard (if enabled)"
  value = var.enable_monitoring ? format(
    "https://console.cloud.google.com/monitoring/dashboards/custom/%s?project=%s",
    google_monitoring_dashboard.gitea[0].id,
    var.project_id
  ) : "Monitoring not enabled"
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if configured)"
  value       = var.enable_monitoring && var.alert_email != "" ? google_monitoring_notification_channel.email[0].id : "No notification channel configured"
}

# ============================================================================
# EVIDENCE & COMPLIANCE
# ============================================================================

output "evidence_file_path" {
  description = "Path to the deployment evidence JSON file"
  value       = local_file.deployment_evidence.filename
}

output "compliance_controls" {
  description = "CMMC and NIST compliance controls implemented"
  value = {
    cmmc_level = "2"
    nist_sp    = "800-171 Rev. 2"
    controls = [
      "AC.L2-3.1.1 - Authorized Access Control",
      "AC.L2-3.1.5 - Least Privilege",
      "AU.L2-3.3.1 - Event Logging",
      "AU.L2-3.3.4 - Audit Record Review",
      "AU.L2-3.3.8 - Protection of Audit Information",
      "CM.L2-3.4.2 - System Baseline Configuration",
      "CM.L2-3.4.6 - Least Functionality",
      "CP.L2-3.11.1 - System Backup",
      "CP.L2-3.11.2 - Recovery Testing",
      "IA.L2-3.5.1 - Identification and Authentication",
      "IA.L2-3.5.7 - Password Complexity",
      "SC.L2-3.13.1 - Boundary Protection",
      "SC.L2-3.13.5 - Publicly Accessible Systems",
      "SC.L2-3.13.8 - Transmission Confidentiality",
      "SC.L2-3.13.11 - Cryptographic Protection",
      "SC.L2-3.13.15 - System Integrity",
      "SC.L2-3.13.16 - Information at Rest",
      "SI.L2-3.14.1 - System Monitoring",
      "SI.L2-3.14.2 - System Monitoring",
      "SI.L2-3.14.3 - Security Alerts",
      "SI.L2-3.14.6 - Information System Monitoring"
    ]
  }
}

# ============================================================================
# BACKUP & RECOVERY
# ============================================================================

output "backup_schedule_enabled" {
  description = "Whether automated backups are enabled"
  value       = var.enable_automated_backups
}

output "backup_retention_days" {
  description = "Number of days backups are retained"
  value       = var.backup_retention_days
}

output "snapshot_policy_name" {
  description = "Name of the disk snapshot policy"
  value       = google_compute_resource_policy.daily_backup.name
}

output "dr_enabled" {
  description = "Whether cross-region disaster recovery is enabled"
  value       = var.enable_cross_region_backup
}

# ============================================================================
# ADMINISTRATIVE INFORMATION
# ============================================================================

output "gitea_admin_username" {
  description = "Gitea administrator username"
  value       = var.gitea_admin_username
}

output "gitea_admin_email" {
  description = "Gitea administrator email"
  value       = var.gitea_admin_email
}

output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = terraform.version
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

# ============================================================================
# USEFUL COMMANDS
# ============================================================================

output "useful_commands" {
  description = "Useful commands for managing the Gitea deployment"
  value = {
    ssh_to_instance = var.enable_iap ? "gcloud compute ssh --zone=${var.zone} ${google_compute_instance.gitea_server.name} --project=${var.project_id} --tunnel-through-iap" : "ssh user@${google_compute_address.gitea_ip.address}"

    view_startup_logs = "gcloud compute instances get-serial-port-output ${google_compute_instance.gitea_server.name} --zone=${var.zone} --project=${var.project_id}"

    restart_instance = "gcloud compute instances restart ${google_compute_instance.gitea_server.name} --zone=${var.zone} --project=${var.project_id}"

    create_snapshot = "gcloud compute disks snapshot ${google_compute_instance.gitea_server.name} --zone=${var.zone} --project=${var.project_id}"

    view_logs = "gcloud logging read 'resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${google_compute_instance.gitea_server.instance_id}\"' --project=${var.project_id} --limit=50"

    list_secrets = var.enable_secret_manager ? "gcloud secrets list --project=${var.project_id}" : "Secret Manager not enabled"

    backup_command = "gsutil -m cp -r gs://${google_storage_bucket.backup.name}/* ./backups/"

    evidence_command = "gsutil -m cp -r gs://${google_storage_bucket.evidence.name}/* ./evidence/"
  }
}

# ============================================================================
# POST-DEPLOYMENT CHECKLIST
# ============================================================================

output "post_deployment_checklist" {
  description = "Actions to complete after deployment"
  value = [
    "1. Configure DNS to point ${var.gitea_domain} to ${google_compute_address.gitea_ip.address}",
    "2. Obtain and configure SSL certificate for HTTPS",
    "3. Access Gitea at https://${var.gitea_domain} and complete setup",
    "4. Configure backup verification procedures",
    "5. Test monitoring alerts by simulating failures",
    "6. Review and approve firewall rules",
    "7. Enable audit log review procedures",
    "8. Configure additional users and repositories",
    "9. Set up CI/CD runners if needed",
    "10. Document recovery procedures"
  ]
}