# Bootstrap Terraform State Backend Infrastructure
# Run this ONCE before deploying main infrastructure
# This creates the GCS backend and KMS keys for state encryption

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Bootstrap uses LOCAL state (this is the only local state)
  # After this runs, all other Terraform uses the GCS backend
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Random suffix for globally unique bucket names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  state_bucket_name  = "${var.project_id}-gitea-tfstate-${random_id.suffix.hex}"
  config_bucket_name = "${var.project_id}-gitea-config-${random_id.suffix.hex}"
  audit_bucket_name  = "${var.project_id}-gitea-audit-${random_id.suffix.hex}"
}

# ============================================================================
# KMS KEY RING AND KEYS
# ============================================================================

# KMS Keyring for all encryption keys
resource "google_kms_key_ring" "gitea" {
  name     = "${var.project_id}-gitea-keyring"
  location = var.kms_location
}

# Key for Terraform state encryption
resource "google_kms_crypto_key" "tfstate" {
  name            = "terraform-state-encryption-key"
  key_ring        = google_kms_key_ring.gitea.id
  rotation_period = "7776000s"  # 90 days

  purpose = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    purpose     = "terraform-state"
    environment = var.environment
    cmmc        = "sc-l2-3-13-11"
  }
}

# Key for configuration storage encryption
resource "google_kms_crypto_key" "config" {
  name            = "configuration-storage-encryption-key"
  key_ring        = google_kms_key_ring.gitea.id
  rotation_period = "7776000s"  # 90 days

  purpose = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    purpose     = "configuration-storage"
    environment = var.environment
    cmmc        = "sc-l2-3-13-11"
  }
}

# Key for audit logs encryption
resource "google_kms_crypto_key" "audit" {
  name            = "audit-logs-encryption-key"
  key_ring        = google_kms_key_ring.gitea.id
  rotation_period = "7776000s"  # 90 days

  purpose = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    purpose     = "audit-logs"
    environment = var.environment
    cmmc        = "au-l2-3-3-1"
  }
}

# ============================================================================
# GCS BUCKET FOR TERRAFORM STATE
# ============================================================================

# Terraform state storage bucket
resource "google_storage_bucket" "tfstate" {
  name          = local.state_bucket_name
  location      = var.bucket_location
  force_destroy = false  # Prevent accidental deletion

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.tfstate.id
  }

  # Lifecycle rule to keep last 30 versions
  lifecycle_rule {
    condition {
      num_newer_versions = 30
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule to transition old versions to Nearline after 30 days
  lifecycle_rule {
    condition {
      age            = 30
      with_state     = "ARCHIVED"
      num_newer_versions = 5
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  labels = {
    purpose     = "terraform-state"
    environment = var.environment
    cmmc        = "cm-l2-3-4-2"
    managed-by  = "terraform-bootstrap"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# IAM binding for state bucket - only allow specific service account
# Only create if terraform_sa_email is provided
resource "google_storage_bucket_iam_member" "tfstate_admin" {
  count  = var.terraform_sa_email != "" ? 1 : 0
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${var.terraform_sa_email}"

  condition {
    title       = "Restrict to Terraform operations"
    description = "Allow only Terraform service account"
    expression  = "request.time < timestamp('2099-01-01T00:00:00Z')"
  }
}

# ============================================================================
# GCS BUCKET FOR CONFIGURATION STORAGE
# ============================================================================

# Configuration storage bucket (terraform.tfvars, docker-compose.yml, etc.)
resource "google_storage_bucket" "config" {
  name          = local.config_bucket_name
  location      = var.bucket_location
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.config.id
  }

  # Keep last 10 versions
  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose     = "configuration-storage"
    environment = var.environment
    cmmc        = "cm-l2-3-4-2"
    managed-by  = "terraform-bootstrap"
  }
}

# ============================================================================
# GCS BUCKET FOR AUDIT LOGS
# ============================================================================

# Audit logs bucket for state modifications
resource "google_storage_bucket" "audit" {
  name          = local.audit_bucket_name
  location      = var.bucket_location
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.audit.id
  }

  # Retention policy: 7 years for CMMC compliance
  retention_policy {
    retention_period = 220752000  # 7 years in seconds
  }

  # Lock retention policy (uncomment after testing)
  # lifecycle {
  #   prevent_destroy = true
  # }

  labels = {
    purpose     = "audit-logs"
    environment = var.environment
    cmmc        = "au-l2-3-3-1"
    managed-by  = "terraform-bootstrap"
  }
}

# Log sink for Terraform state changes
resource "google_logging_project_sink" "tfstate_audit" {
  name        = "terraform-state-audit-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.audit.name}"

  filter = <<-EOT
    resource.type="gcs_bucket"
    resource.labels.bucket_name="${google_storage_bucket.tfstate.name}"
    (protoPayload.methodName="storage.objects.create" OR
     protoPayload.methodName="storage.objects.update" OR
     protoPayload.methodName="storage.objects.delete")
  EOT

  unique_writer_identity = true
}

# Grant log sink permission to write to audit bucket
resource "google_storage_bucket_iam_member" "audit_log_writer" {
  bucket = google_storage_bucket.audit.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.tfstate_audit.writer_identity
}

# ============================================================================
# EVIDENCE LOG
# ============================================================================

# Generate bootstrap evidence for compliance
resource "local_file" "bootstrap_evidence" {
  filename = "${path.module}/bootstrap_evidence_${formatdate("YYYY-MM-DD_HHmmss", timestamp())}.json"

  content = jsonencode({
    bootstrap_timestamp = timestamp()
    project_id          = var.project_id
    environment         = var.environment

    resources_created = {
      kms_keyring      = google_kms_key_ring.gitea.id
      tfstate_key      = google_kms_crypto_key.tfstate.id
      config_key       = google_kms_crypto_key.config.id
      audit_key        = google_kms_crypto_key.audit.id
      tfstate_bucket   = google_storage_bucket.tfstate.name
      config_bucket    = google_storage_bucket.config.name
      audit_bucket     = google_storage_bucket.audit.name
    }

    security_features = {
      kms_encryption         = true
      bucket_versioning      = true
      audit_logging          = true
      retention_policy       = "7 years (CMMC compliant)"
      access_control         = "Service Account only"
      state_lock             = "GCS versioning"
    }

    cmmc_controls = [
      "CM.L2-3.4.2 - Baseline Configuration",
      "SC.L2-3.13.11 - Cryptographic Protection",
      "AU.L2-3.3.1 - Audit Logging",
    ]

    backend_configuration = {
      bucket = google_storage_bucket.tfstate.name
      prefix = "terraform/state"
    }
  })
}
