# Cloud Storage Configuration for Gitea GCP Deployment
# CMMC 2.0 Level 2 Compliant Storage
# NIST SP 800-171 Rev. 2 Controls Implementation

# ============================================================================
# EVIDENCE BUCKET - AU.L2-3.3.1: Event Logging & AU.L2-3.3.4: Audit Record Review
# ============================================================================

resource "google_storage_bucket" "evidence" {
  name          = "${local.evidence_bucket}-${random_id.bucket_suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"

  # Force destroy for Terraform (be careful in production)
  force_destroy = var.environment != "prod"

  # Uniform bucket-level access for simplified IAM - AC.L2-3.1.1
  uniform_bucket_level_access = true

  # Labels for CMMC compliance tracking
  labels = local.cmmc_labels.evidence_bucket

  # Versioning for audit trail integrity - AU.L2-3.3.8: Protection of Audit Information
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Retention policy - 7 years for CMMC compliance
  retention_policy {
    retention_period = var.evidence_retention_days * 86400  # Convert days to seconds
    is_locked       = var.environment == "prod" ? true : false  # Lock in production
  }

  # Lifecycle rules for automated management
  lifecycle_rule {
    condition {
      age                   = var.evidence_retention_days + 30  # Delete 30 days after retention
      matches_storage_class = ["STANDARD"]
    }
    action {
      type = "Delete"
    }
  }

  # Transition to cheaper storage after 90 days
  lifecycle_rule {
    condition {
      age                   = 90
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # Transition to Archive after 365 days
  lifecycle_rule {
    condition {
      age                   = 365
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  # Encryption with CMEK - SC.L2-3.13.11: Cryptographic Protection
  dynamic "encryption" {
    for_each = var.enable_kms ? [1] : []
    content {
      default_kms_key_name = google_kms_crypto_key.storage_key[0].id
    }
  }

  # Logging configuration - AU.L2-3.3.1
  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "evidence-bucket-logs/"
  }

  # CORS configuration (if needed for web access)
  cors {
    origin          = ["https://${var.gitea_domain}"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Public access prevention - AC.L2-3.1.20: External System Connections
  public_access_prevention = "enforced"

  depends_on = [
    google_storage_bucket.logs,  # Ensure logs bucket exists first
    google_kms_crypto_key.storage_key,
  ]
}

# ============================================================================
# BACKUP BUCKET - CP.L2-3.11.1: System Backup & CP.L2-3.11.2: Recovery Testing
# ============================================================================

resource "google_storage_bucket" "backup" {
  name          = "${local.backup_bucket}-${random_id.bucket_suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"

  force_destroy = var.environment != "prod"

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Labels for identification
  labels = merge(local.common_labels, {
    "purpose"              = "backup"
    "retention-days"       = tostring(var.backup_retention_days)
    "cmmc-control"        = "cp-l2-3-11-1"
  })

  # Enable versioning for backup integrity
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Retention policy for backups
  retention_policy {
    retention_period = var.backup_retention_days * 86400
    is_locked       = false  # Don't lock to allow flexibility
  }

  # Lifecycle rules for backup rotation
  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Delete old versions after 7 days
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }

  # Encryption with CMEK
  dynamic "encryption" {
    for_each = var.enable_kms ? [1] : []
    content {
      default_kms_key_name = google_kms_crypto_key.storage_key[0].id
    }
  }

  # Logging configuration
  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "backup-bucket-logs/"
  }

  # Public access prevention
  public_access_prevention = "enforced"

  depends_on = [
    google_storage_bucket.logs,
    google_kms_crypto_key.storage_key,
  ]
}

# ============================================================================
# LOGS BUCKET - AU.L2-3.3.1: Event Logging & SI.L2-3.14.1: System Monitoring
# ============================================================================

resource "google_storage_bucket" "logs" {
  name          = "${local.logs_bucket}-${random_id.bucket_suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"

  force_destroy = var.environment != "prod"

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Labels for identification
  labels = merge(local.common_labels, {
    "purpose"              = "logging"
    "retention-days"       = tostring(var.logs_retention_days)
    "cmmc-control"        = "au-l2-3-3-1"
    "nist-control"        = "si-l2-3-14-1"
  })

  # Enable versioning
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Retention policy for logs
  retention_policy {
    retention_period = var.logs_retention_days * 86400
    is_locked       = false
  }

  # Lifecycle rules for log management
  lifecycle_rule {
    condition {
      age = var.logs_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Transition to cheaper storage after 30 days
  lifecycle_rule {
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # Delete non-current versions after 30 days
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
    }
    action {
      type = "Delete"
    }
  }

  # Encryption with CMEK
  dynamic "encryption" {
    for_each = var.enable_kms ? [1] : []
    content {
      default_kms_key_name = google_kms_crypto_key.storage_key[0].id
    }
  }

  # Public access prevention
  public_access_prevention = "enforced"

  depends_on = [
    google_kms_crypto_key.storage_key,
  ]
}

# ============================================================================
# CROSS-REGION BACKUP BUCKET (DISASTER RECOVERY)
# ============================================================================

resource "google_storage_bucket" "backup_dr" {
  count = var.enable_cross_region_backup ? 1 : 0

  name          = "${local.backup_bucket}-dr-${random_id.bucket_suffix.hex}"
  location      = var.backup_region
  storage_class = "STANDARD"

  force_destroy = var.environment != "prod"

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Labels for DR identification
  labels = merge(local.common_labels, {
    "purpose"              = "disaster-recovery"
    "retention-days"       = tostring(var.backup_retention_days)
    "cmmc-control"        = "cp-l2-3-11-3"
    "replication-source"   = var.region
  })

  # Enable versioning
  versioning {
    enabled = true
  }

  # Retention policy
  retention_policy {
    retention_period = var.backup_retention_days * 86400
    is_locked       = false
  }

  # Lifecycle rules
  lifecycle_rule {
    condition {
      age = var.backup_retention_days * 2  # Keep DR backups longer
    }
    action {
      type = "Delete"
    }
  }

  # Encryption with CMEK
  dynamic "encryption" {
    for_each = var.enable_kms ? [1] : []
    content {
      default_kms_key_name = google_kms_crypto_key.storage_key[0].id
    }
  }

  # Logging
  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "dr-backup-logs/"
  }

  # Public access prevention
  public_access_prevention = "enforced"

  depends_on = [
    google_storage_bucket.logs,
    google_kms_crypto_key.storage_key,
  ]
}

# ============================================================================
# IAM BINDINGS FOR BUCKETS - AC.L2-3.1.1: Authorized Access Control
# ============================================================================

# Evidence bucket IAM - Read/Write for evidence service account
resource "google_storage_bucket_iam_member" "evidence_writer" {
  bucket = google_storage_bucket.evidence.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.evidence_sa.email}"
}

# Evidence bucket IAM - Read-only for Gitea service account
resource "google_storage_bucket_iam_member" "evidence_reader" {
  bucket = google_storage_bucket.evidence.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.gitea_sa.email}"
}

# Backup bucket IAM - Read/Write for Gitea service account
resource "google_storage_bucket_iam_member" "backup_admin" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gitea_sa.email}"
}

# Logs bucket IAM - Write for all service accounts
resource "google_storage_bucket_iam_member" "logs_writer_gitea" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.gitea_sa.email}"
}

resource "google_storage_bucket_iam_member" "logs_writer_evidence" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.evidence_sa.email}"
}

# DR backup bucket IAM (if enabled)
resource "google_storage_bucket_iam_member" "dr_backup_admin" {
  count = var.enable_cross_region_backup ? 1 : 0

  bucket = google_storage_bucket.backup_dr[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gitea_sa.email}"
}

# ============================================================================
# STORAGE TRANSFER SERVICE FOR BACKUP REPLICATION (OPTIONAL)
# ============================================================================

resource "google_storage_transfer_job" "backup_replication" {
  count = var.enable_cross_region_backup ? 1 : 0

  description = "Replicate backups to DR region for disaster recovery"
  project     = var.project_id

  transfer_spec {
    gcs_data_source {
      bucket_name = google_storage_bucket.backup.name
    }

    gcs_data_sink {
      bucket_name = google_storage_bucket.backup_dr[0].name
    }

    transfer_options {
      delete_objects_unique_in_sink = false
      delete_objects_from_source_after_transfer = false
      overwrite_objects_already_existing_in_sink = true
    }
  }

  schedule {
    schedule_start_date {
      year  = tonumber(formatdate("YYYY", timestamp()))
      month = tonumber(formatdate("MM", timestamp()))
      day   = tonumber(formatdate("DD", timestamp()))
    }

    start_time_of_day {
      hours   = 3
      minutes = 0
      seconds = 0
      nanos   = 0
    }

    repeat_interval = "86400s"  # Daily
  }

  depends_on = [
    google_storage_bucket.backup,
    google_storage_bucket.backup_dr,
  ]
}

# ============================================================================
# BUCKET NOTIFICATIONS (OPTIONAL)
# ============================================================================

# Pub/Sub topic for bucket notifications
resource "google_pubsub_topic" "storage_notifications" {
  count = var.enable_monitoring ? 1 : 0

  name = "${local.name_prefix}-storage-notifications"

  labels = merge(local.common_labels, {
    "purpose" = "storage-events"
  })

  message_retention_duration = "86400s"  # 1 day

  # Enable CMEK encryption
#   dynamic "encryption_config" {
#     for_each = var.enable_kms ? [1] : []
#     content {
#       kms_key_name = google_kms_crypto_key.storage_key[0].id
#     }
#   }
}

# Notification for evidence bucket
resource "google_storage_notification" "evidence_notification" {
  count = var.enable_monitoring ? 1 : 0

  bucket         = google_storage_bucket.evidence.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.storage_notifications[0].id

  event_types = [
    "OBJECT_FINALIZE",
    "OBJECT_DELETE",
  ]

  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

# IAM for Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  count = var.enable_monitoring ? 1 : 0

  topic  = google_pubsub_topic.storage_notifications[0].id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}