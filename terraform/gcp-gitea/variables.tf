# Input Variables for Gitea GCP Deployment
# Terraform Configuration

# ============================================================================
# PROJECT & REGION
# ============================================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, lowercase letters, digits, or hyphens."
  }
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for Compute Engine instance"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# ============================================================================
# BOOTSTRAP RESOURCES
# ============================================================================

variable "terraform_state_bucket" {
  description = "Name of the GCS bucket for Terraform state (created by bootstrap)"
  type        = string
  default     = ""

  validation {
    condition     = var.terraform_state_bucket == "" || can(regex("^[a-z0-9][a-z0-9-_]{1,61}[a-z0-9]$", var.terraform_state_bucket))
    error_message = "State bucket name must be 3-63 characters, lowercase letters, digits, hyphens, or underscores."
  }
}

variable "kms_keyring_name" {
  description = "Name of the KMS keyring (created by bootstrap)"
  type        = string
  default     = ""
}

variable "kms_keyring_location" {
  description = "Location of the KMS keyring"
  type        = string
  default     = "us"
}

# ============================================================================
# NETWORKING
# ============================================================================

variable "subnet_cidr" {
  description = "CIDR range for Gitea subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT for outbound internet access"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr_ranges" {
  description = "CIDR ranges allowed to SSH to the instance (use IAP for best security)"
  type        = list(string)
  default     = ["35.235.240.0/20"] # IAP IP range
}

variable "allowed_https_cidr_ranges" {
  description = "CIDR ranges allowed for HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_git_ssh_cidr_ranges" {
  description = "CIDR ranges allowed for Git SSH access"
  type        = list(string)
  default     = []  # Empty = deny all, configure for your IPs
}

# ============================================================================
# COMPUTE INSTANCE
# ============================================================================

variable "machine_type" {
  description = "Compute Engine machine type"
  type        = string
  default     = "e2-standard-8"  # 8 vCPU, 32GB RAM
}

variable "cpu_platform" {
  description = "Minimum CPU platform for the instance"
  type        = string
  default     = "Intel Cascade Lake"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 200

  validation {
    condition     = var.boot_disk_size >= 100 && var.boot_disk_size <= 1000
    error_message = "Boot disk size must be between 100GB and 1000GB."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type (pd-standard, pd-ssd, pd-balanced)"
  type        = string
  default     = "pd-ssd"
}

variable "data_disk_size" {
  description = "Data disk size in GB for Docker volumes"
  type        = number
  default     = 500

  validation {
    condition     = var.data_disk_size >= 100 && var.data_disk_size <= 10000
    error_message = "Data disk size must be between 100GB and 10000GB."
  }
}

variable "data_disk_type" {
  description = "Data disk type (pd-standard, pd-ssd, pd-balanced)"
  type        = string
  default     = "pd-ssd"
}

# ============================================================================
# SECURITY
# ============================================================================

variable "enable_secure_boot" {
  description = "Enable Secure Boot for Shielded VM"
  type        = bool
  default     = true
}

variable "enable_vtpm" {
  description = "Enable vTPM for Shielded VM"
  type        = bool
  default     = true
}

variable "enable_integrity_monitoring" {
  description = "Enable integrity monitoring for Shielded VM"
  type        = bool
  default     = true
}

variable "enable_os_login" {
  description = "Enable OS Login for SSH access management"
  type        = bool
  default     = true
}

variable "enable_iap" {
  description = "Enable Identity-Aware Proxy for SSH access"
  type        = bool
  default     = true
}

variable "enable_kms" {
  description = "Enable Cloud KMS for encryption keys"
  type        = bool
  default     = true
}

variable "enable_secret_manager" {
  description = "Enable Secret Manager for sensitive credentials"
  type        = bool
  default     = true
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor WAF protection"
  type        = bool
  default     = true
}

variable "enable_vpc_sc" {
  description = "Enable VPC Service Controls (requires organization setup)"
  type        = bool
  default     = false
}

variable "enable_shielded_vm" {
  description = "Enable Shielded VM features"
  type        = bool
  default     = true
}

# ============================================================================
# GITEA CONFIGURATION
# ============================================================================

variable "gitea_domain" {
  description = "Domain name for Gitea (e.g., git.example.com)"
  type        = string
}

variable "gitea_admin_username" {
  description = "Gitea admin username"
  type        = string
  default     = "admin"
}

variable "gitea_admin_password" {
  description = "Gitea admin password (min 14 chars, complex). Leave null to auto-generate."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.gitea_admin_password == null || (length(var.gitea_admin_password) >= 14 && can(regex("[A-Z]", var.gitea_admin_password)) && can(regex("[a-z]", var.gitea_admin_password)) && can(regex("[0-9]", var.gitea_admin_password)) && can(regex("[^A-Za-z0-9]", var.gitea_admin_password)))
    error_message = "Password must be at least 14 characters with uppercase, lowercase, digit, and special character."
  }
}

variable "gitea_admin_email" {
  description = "Gitea admin email address"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL password. Leave null to auto-generate."
  type        = string
  default     = null
  sensitive   = true
}

variable "gitea_disable_registration" {
  description = "Disable public user registration"
  type        = bool
  default     = true
}

variable "gitea_require_signin_view" {
  description = "Require sign-in to view repositories"
  type        = bool
  default     = false
}

# ============================================================================
# STORAGE
# ============================================================================

variable "evidence_retention_days" {
  description = "Evidence retention in days (CMMC requires 7 years = 2555 days)"
  type        = number
  default     = 2555
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 30
}

variable "logs_retention_days" {
  description = "Logs retention in days"
  type        = number
  default     = 90
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on GCS buckets"
  type        = bool
  default     = true
}

# ============================================================================
# MONITORING & ALERTING
# ============================================================================

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboards and alerts"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""
}

variable "enable_uptime_checks" {
  description = "Enable uptime checks for Gitea"
  type        = bool
  default     = true
}

# ============================================================================
# BACKUP & DISASTER RECOVERY
# ============================================================================

variable "enable_automated_backups" {
  description = "Enable automated daily backups via Cloud Scheduler"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cron schedule for automated backups (default: 2 AM UTC daily)"
  type        = string
  default     = "0 2 * * *"
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup replication for DR"
  type        = bool
  default     = false
}

variable "backup_region" {
  description = "Secondary region for backup replication"
  type        = string
  default     = "us-east1"
}

# ============================================================================
# LABELS & TAGGING
# ============================================================================

variable "additional_labels" {
  description = "Additional labels for all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# ADVANCED CONFIGURATION
# ============================================================================

variable "enable_docker_gcr" {
  description = "Configure Docker to use GCR for container images"
  type        = bool
  default     = false
}

variable "custom_startup_script" {
  description = "Custom startup script to append to the default script"
  type        = string
  default     = ""
}

variable "metadata" {
  description = "Additional instance metadata"
  type        = map(string)
  default     = {}
}

variable "enable_iam_conditions" {
  description = "Enable IAM conditions for enhanced security"
  type        = bool
  default     = false
}
