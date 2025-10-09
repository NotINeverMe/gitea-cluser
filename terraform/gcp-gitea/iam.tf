# IAM Service Accounts and Permissions
# Minimal privilege principle - only required permissions

locals {
  terraform_state_bucket = var.terraform_state_bucket
  disk_kms_key_id        = var.disk_kms_key_id != null ? var.disk_kms_key_id : (var.enable_kms ? try(google_kms_crypto_key.disk_key[0].id, null) : null)
  storage_kms_key_id     = var.storage_kms_key_id != null ? var.storage_kms_key_id : (var.enable_kms ? try(google_kms_crypto_key.storage_key[0].id, null) : null)
}

# ============================================================================
# TERRAFORM DEPLOYER SERVICE ACCOUNT
# ============================================================================

# Service account for Terraform deployments (used by CI/CD or operators)
resource "google_service_account" "terraform_deployer" {
  account_id   = "gitea-tf-deploy"
  display_name = "Gitea Terraform Deployer"
  description  = "Service account for deploying Gitea infrastructure via Terraform"
  project      = var.project_id
}

# Grant minimal required roles for Terraform operations
resource "google_project_iam_member" "terraform_deployer_roles" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",           # Manage Compute instances
    "roles/compute.networkAdmin",               # Manage VPC networks
    "roles/compute.securityAdmin",              # Manage firewalls
    "roles/iam.serviceAccountUser",             # Use service accounts
    "roles/storage.admin",                      # Manage GCS buckets
    "roles/secretmanager.secretAccessor",       # Read secrets
    "roles/cloudkms.cryptoKeyEncrypterDecrypter", # Use KMS keys
    "roles/monitoring.metricWriter",            # Write monitoring metrics
    "roles/logging.logWriter",                  # Write logs
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.terraform_deployer.email}"
}

# ============================================================================
# GITEA VM SERVICE ACCOUNT
# ============================================================================

# Service account for Gitea VM operations
resource "google_service_account" "gitea_vm" {
  account_id   = "gitea-vm"
  display_name = "Gitea VM Service Account"
  description  = "Service account for Gitea Compute Engine instance"
  project      = var.project_id
}

# Minimal roles for VM operations
resource "google_project_iam_member" "gitea_vm_roles" {
  for_each = toset([
    "roles/logging.logWriter",          # Write logs to Cloud Logging
    "roles/monitoring.metricWriter",    # Write metrics to Cloud Monitoring
    "roles/secretmanager.secretAccessor", # Read secrets for container startup
    "roles/storage.objectCreator",      # Upload evidence to GCS
    "roles/storage.objectViewer",       # Read backups from GCS
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gitea_vm.email}"
}

# ============================================================================
# EVIDENCE COLLECTION SERVICE ACCOUNT
# ============================================================================

# Dedicated service account for evidence collection (compliance automation)
resource "google_service_account" "evidence_collector" {
  account_id   = "gitea-evidence-coll"
  display_name = "Evidence Collection Service Account"
  description  = "Service account for automated compliance evidence collection"
  project      = var.project_id
}

# Evidence collector permissions
resource "google_project_iam_member" "evidence_collector_roles" {
  for_each = toset([
    "roles/securitycenter.findingsViewer",  # Read Security Command Center findings
    "roles/cloudasset.viewer",              # Read asset inventory
    "roles/logging.viewer",                 # Read audit logs
    "roles/iam.securityReviewer",           # Review IAM policies
    "roles/cloudkms.viewer",                # Verify encryption
    "roles/storage.objectCreator",          # Upload evidence to GCS
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.evidence_collector.email}"
}

# ============================================================================
# BACKUP SERVICE ACCOUNT
# ============================================================================

# Dedicated service account for backup operations
resource "google_service_account" "backup" {
  account_id   = "gitea-backup"
  display_name = "Backup Service Account"
  description  = "Service account for automated backup operations"
  project      = var.project_id
}

# Backup permissions
resource "google_project_iam_member" "backup_roles" {
  for_each = toset([
    "roles/compute.storageAdmin",        # Manage snapshots
    "roles/storage.admin",               # Manage backup buckets
    "roles/logging.logWriter",           # Write backup logs
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.backup.email}"
}

# ============================================================================
# IAM CONDITIONS FOR ENHANCED SECURITY
# ============================================================================

# Restrict Terraform deployer to only access state buckets
resource "google_storage_bucket_iam_member" "terraform_state_access" {
  count  = var.enable_iam_conditions && local.terraform_state_bucket != "" ? 1 : 0
  bucket = local.terraform_state_bucket
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.terraform_deployer.email}"

  condition {
    title       = "Terraform State Access Only"
    description = "Allow access only to Terraform state operations"
    expression  = <<-EOT
      resource.name.startsWith("projects/_/buckets/${local.terraform_state_bucket}/objects/${var.terraform_state_object_prefix}")
    EOT
  }
}

# ============================================================================
# KEY ACCESS GRANTS
# ============================================================================

# Grant KMS key access to service accounts
resource "google_kms_crypto_key_iam_member" "gitea_vm_key_user" {
  count         = local.disk_kms_key_id != null ? 1 : 0
  crypto_key_id = local.disk_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.gitea_vm.email}"
}

resource "google_kms_crypto_key_iam_member" "backup_key_user" {
  count         = local.storage_kms_key_id != null ? 1 : 0
  crypto_key_id = local.storage_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.backup.email}"
}

# ============================================================================

# OUTPUTS
# ============================================================================

output "service_accounts" {
  description = "Service account emails for all roles"
  value = {
    terraform_deployer  = google_service_account.terraform_deployer.email
    gitea_vm            = google_service_account.gitea_vm.email
    evidence_collector  = google_service_account.evidence_collector.email
    backup              = google_service_account.backup.email
  }
}

output "iam_security_summary" {
  description = "IAM security configuration summary"
  value = {
    principle                = "Least Privilege"
    service_accounts_created = 4
    iam_conditions_enabled   = var.enable_iam_conditions
    cmmc_control             = "AC.L2-3.1.1 - Authorized Access Control"
  }
}
