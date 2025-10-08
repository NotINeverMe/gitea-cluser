# Security Resources for Gitea GCP Deployment
# CMMC 2.0 Level 2 Security Controls
# NIST SP 800-171 Rev. 2 Compliance

# ============================================================================
# CLOUD KMS - SC.L2-3.13.11: Cryptographic Protection
# ============================================================================

# KMS Keyring for encryption keys
resource "google_kms_key_ring" "gitea_keyring" {
  count = var.enable_kms ? 1 : 0

  name     = "${local.name_prefix}-keyring"
  location = var.region  # Use regional to match GCS bucket location
}

# Crypto key for disk encryption - SC.L2-3.13.16: Information at Rest
resource "google_kms_crypto_key" "disk_key" {
  count = var.enable_kms ? 1 : 0

  name            = "${local.name_prefix}-disk-key"
  key_ring        = google_kms_key_ring.gitea_keyring[0].id
  rotation_period = "7776000s"  # 90 days rotation

  # Key purpose
  purpose = "ENCRYPT_DECRYPT"

  # Version template
  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  # Labels for compliance tracking
  labels = merge(local.common_labels, {
    "purpose"      = "disk-encryption"
    "cmmc-control" = "sc-l2-3-13-11"
    "nist-control" = "sc-l2-3-13-16"
  })

  lifecycle {
    prevent_destroy = false  # Set to true in production
  }
}

# Crypto key for storage encryption
resource "google_kms_crypto_key" "storage_key" {
  count = var.enable_kms ? 1 : 0

  name            = "${local.name_prefix}-storage-key"
  key_ring        = google_kms_key_ring.gitea_keyring[0].id
  rotation_period = "7776000s"  # 90 days

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  labels = merge(local.common_labels, {
    "purpose"      = "storage-encryption"
    "cmmc-control" = "sc-l2-3-13-11"
  })

  lifecycle {
    prevent_destroy = false
  }
}

# Crypto key for secrets encryption
resource "google_kms_crypto_key" "secrets_key" {
  count = var.enable_kms ? 1 : 0

  name            = "${local.name_prefix}-secrets-key"
  key_ring        = google_kms_key_ring.gitea_keyring[0].id
  rotation_period = "2592000s"  # 30 days - more frequent for secrets

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  labels = merge(local.common_labels, {
    "purpose"      = "secrets-encryption"
    "cmmc-control" = "sc-l2-3-13-11"
  })

  lifecycle {
    prevent_destroy = false
  }
}

# ============================================================================
# SERVICE ACCOUNTS - AC.L2-3.1.5: Least Privilege
# ============================================================================

# Service account for Gitea VM instance
resource "google_service_account" "gitea_sa" {
  account_id   = local.gitea_sa
  display_name = "Gitea Server Service Account"
  description  = "Service account for Gitea VM with least privilege access"
}

# Service account for evidence collection
resource "google_service_account" "evidence_sa" {
  account_id   = local.evidence_sa
  display_name = "Evidence Collection Service Account"
  description  = "Service account for audit evidence collection and compliance"
}

# Service account for backup operations
resource "google_service_account" "backup_sa" {
  account_id   = "gitea-backup-sa"
  display_name = "Backup Service Account"
  description  = "Service account for automated backup operations"
}

# ============================================================================
# SECRET MANAGER - IA.L2-3.5.7: Password Complexity
# ============================================================================

# Secret for Gitea admin password
resource "google_secret_manager_secret" "admin_password" {
  count = var.enable_secret_manager ? 1 : 0

  secret_id = local.admin_password_secret

  labels = merge(local.common_labels, {
    "purpose"      = "gitea-admin"
    "cmmc-control" = "ia-l2-3-5-7"
  })

  replication {
    user_managed {
      replicas {
        location = var.region

        # CMEK encryption disabled - requires service identity setup
        # dynamic "customer_managed_encryption" {
        #   for_each = var.enable_kms ? [1] : []
        #   content {
        #     kms_key_name = google_kms_crypto_key.secrets_key[0].id
        #   }
        # }
      }
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Secret version for admin password
resource "google_secret_manager_secret_version" "admin_password_version" {
  count = var.enable_secret_manager ? 1 : 0

  secret      = google_secret_manager_secret.admin_password[0].id
  secret_data = var.gitea_admin_password != null ? var.gitea_admin_password : random_password.gitea_admin_password[0].result

  lifecycle {
    ignore_changes = [secret_data]  # Prevent regeneration on each apply
  }
}

# Secret for PostgreSQL password
resource "google_secret_manager_secret" "db_password" {
  count = var.enable_secret_manager ? 1 : 0

  secret_id = local.db_password_secret

  labels = merge(local.common_labels, {
    "purpose"      = "postgres-db"
    "cmmc-control" = "ia-l2-3-5-7"
  })

  replication {
    user_managed {
      replicas {
        location = var.region

        # CMEK encryption disabled - requires service identity setup
        # dynamic "customer_managed_encryption" {
        #   for_each = var.enable_kms ? [1] : []
        #   content {
        #     kms_key_name = google_kms_crypto_key.secrets_key[0].id
        #   }
        # }
      }
    }
  }
}

# Secret version for database password
resource "google_secret_manager_secret_version" "db_password_version" {
  count = var.enable_secret_manager ? 1 : 0

  secret      = google_secret_manager_secret.db_password[0].id
  secret_data = var.postgres_password != null ? var.postgres_password : random_password.postgres_password[0].result

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Secret for Gitea runner token
resource "google_secret_manager_secret" "runner_token" {
  count = var.enable_secret_manager ? 1 : 0

  secret_id = local.runner_token_secret

  labels = merge(local.common_labels, {
    "purpose"      = "gitea-runner"
    "cmmc-control" = "ia-l2-3-5-1"
  })

  replication {
    user_managed {
      replicas {
        location = var.region

        # CMEK encryption disabled - requires service identity setup
        # dynamic "customer_managed_encryption" {
        #   for_each = var.enable_kms ? [1] : []
        #   content {
        #     kms_key_name = google_kms_crypto_key.secrets_key[0].id
        #   }
        # }
      }
    }
  }
}

# Generate random runner token
resource "random_password" "runner_token" {
  length  = 40
  special = false  # Alphanumeric only for runner token
}

# Secret version for runner token
resource "google_secret_manager_secret_version" "runner_token_version" {
  count = var.enable_secret_manager ? 1 : 0

  secret      = google_secret_manager_secret.runner_token[0].id
  secret_data = random_password.runner_token.result

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# ============================================================================
# IAM BINDINGS - AC.L2-3.1.1: Authorized Access Control
# ============================================================================

# Gitea service account permissions
resource "google_project_iam_member" "gitea_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",           # Write logs
    "roles/monitoring.metricWriter",      # Write metrics
    "roles/secretmanager.secretAccessor", # Access secrets
    "roles/storage.objectAdmin",         # Manage storage objects
    "roles/compute.osLogin",             # OS Login access
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gitea_sa.email}"
}

# Evidence service account permissions
resource "google_project_iam_member" "evidence_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",      # Write audit logs
    "roles/monitoring.metricWriter", # Write metrics
    "roles/storage.objectCreator",  # Create evidence objects
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.evidence_sa.email}"
}

# Backup service account permissions
resource "google_project_iam_member" "backup_sa_roles" {
  for_each = toset([
    "roles/compute.instanceAdmin",   # Manage instances for backup
    "roles/storage.objectAdmin",     # Manage backup objects
    "roles/compute.storageAdmin",    # Manage disk snapshots
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.backup_sa.email}"
}

# KMS key IAM bindings
resource "google_kms_crypto_key_iam_member" "disk_key_users" {
  for_each = var.enable_kms ? tomap({
    "gitea-sa"        = google_service_account.gitea_sa.email,
    "compute-service" = "service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com",
  }) : tomap({})

  crypto_key_id = google_kms_crypto_key.disk_key[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${each.value}"
}

resource "google_kms_crypto_key_iam_member" "storage_key_users" {
  for_each = var.enable_kms ? tomap({
    "gitea-sa"        = google_service_account.gitea_sa.email,
    "evidence-sa"     = google_service_account.evidence_sa.email,
    "backup-sa"       = google_service_account.backup_sa.email,
    "storage-service" = "service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com",
  }) : tomap({})

  crypto_key_id = google_kms_crypto_key.storage_key[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${each.value}"
}

# Secret Manager IAM bindings
resource "google_secret_manager_secret_iam_member" "admin_password_access" {
  count = var.enable_secret_manager ? 1 : 0

  secret_id = google_secret_manager_secret.admin_password[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.gitea_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "db_password_access" {
  count = var.enable_secret_manager ? 1 : 0

  secret_id = google_secret_manager_secret.db_password[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.gitea_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "runner_token_access" {
  count = var.enable_secret_manager ? 1 : 0

  secret_id = google_secret_manager_secret.runner_token[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.gitea_sa.email}"
}

# ============================================================================
# VPC SERVICE CONTROLS (OPTIONAL) - SC.L2-3.13.1: Boundary Protection
# ============================================================================

# Note: VPC Service Controls require organization-level setup
# Uncomment and configure if your project is part of an organization

# resource "google_access_context_manager_service_perimeter" "gitea_perimeter" {
#   count = var.enable_vpc_sc ? 1 : 0
#
#   parent = "accessPolicies/${var.access_policy_id}"
#   name   = "accessPolicies/${var.access_policy_id}/servicePerimeters/${local.name_prefix}-perimeter"
#   title  = "Gitea Service Perimeter"
#
#   status {
#     restricted_services = [
#       "storage.googleapis.com",
#       "secretmanager.googleapis.com",
#       "cloudkms.googleapis.com",
#       "compute.googleapis.com",
#     ]
#
#     resources = [
#       "projects/${data.google_project.current.number}",
#     ]
#
#     access_levels = []
#   }
# }

# ============================================================================
# WORKLOAD IDENTITY (FOR GKE INTEGRATION - FUTURE)
# ============================================================================

resource "google_service_account" "workload_identity" {
  count = 0  # Disabled by default

  account_id   = "${local.name_prefix}-workload-identity"
  display_name = "Workload Identity for Gitea"
  description  = "Service account for workload identity binding with Kubernetes"
}

# ============================================================================
# BINARY AUTHORIZATION (OPTIONAL) - CM.L2-3.4.6: Least Functionality
# ============================================================================

# Binary authorization policy for container image verification
resource "google_binary_authorization_policy" "policy" {
  count = 0  # Disabled by default, enable if using containers

  admission_whitelist_patterns {
    name_pattern = "gcr.io/${var.project_id}/*"
  }

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = [
      # Add attestor resource references here
    ]
  }

  description = "Binary authorization policy for container security - CM.L2-3.4.6"
}

# ============================================================================
# ORGANIZATION POLICIES (IF APPLICABLE)
# ============================================================================

# Example organization policies for enhanced security
# These require organization-level permissions

# resource "google_organization_policy" "disable_serial_port" {
#   count = var.apply_org_policies ? 1 : 0
#
#   org_id     = var.org_id
#   constraint = "compute.disableSerialPortAccess"
#
#   boolean_policy {
#     enforced = true
#   }
# }

# resource "google_organization_policy" "require_oslogin" {
#   count = var.apply_org_policies ? 1 : 0
#
#   org_id     = var.org_id
#   constraint = "compute.requireOsLogin"
#
#   boolean_policy {
#     enforced = true
#   }
# }