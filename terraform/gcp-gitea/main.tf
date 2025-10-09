# Main Terraform Configuration for Gitea GCP Deployment
# CMMC 2.0 Level 2 Compliant Infrastructure
# NIST SP 800-171 Rev. 2 Controls Implemented

locals {
  # Common resource naming
  name_prefix = "${var.project_id}-${var.environment}"

  # Network configuration
  network_name    = "${local.name_prefix}-gitea-network"
  subnet_name     = "${local.name_prefix}-gitea-subnet"

  # Instance configuration
  instance_name   = "${local.name_prefix}-gitea-vm"

  # Storage configuration
  evidence_bucket = "${local.name_prefix}-evidence"
  backup_bucket   = "${local.name_prefix}-backups"
  logs_bucket     = "${local.name_prefix}-logs"

  # Service account configuration (short names to meet 30-char limit)
  gitea_sa        = "gitea-sa"
  evidence_sa     = "gitea-evidence"

  # Secret names
  admin_password_secret        = "${local.name_prefix}-gitea-admin-password"
  db_password_secret           = "${local.name_prefix}-postgres-password"
  runner_token_secret          = "${local.name_prefix}-runner-token"
  gitea_secret_key_secret      = "${local.name_prefix}-gitea-secret-key"
  gitea_internal_token_secret  = "${local.name_prefix}-gitea-internal-token"
  gitea_oauth2_jwt_secret      = "${local.name_prefix}-gitea-oauth2-jwt-secret"
  gitea_metrics_token_secret   = "${local.name_prefix}-gitea-metrics-token"

  # Common labels for all resources
  common_labels = merge(
    {
      "environment"    = var.environment
      "managed-by"     = "terraform"
      "project"        = "gitea-devsecops"
      "compliance"     = "cmmc-level-2"
      "nist-800-171"   = "rev-2"
    },
    var.additional_labels
  )

  # CMMC asset category labels
  cmmc_labels = {
    gitea_vm = merge(local.common_labels, {
      "cmmc-asset-category" = "cui"
      "cmmc-controls" = "ac-au-ia-sc"
      "cmmc-level" = "level-2"
    })

    evidence_bucket = merge(local.common_labels, {
      "cmmc-asset-category" = "cui"
      "cmmc-controls" = "au-sc"
      "cmmc-level" = "level-2"
    })
  }
}

# Data source: Get latest Ubuntu 22.04 LTS image
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Data source: Current project
data "google_project" "current" {
  project_id = var.project_id
}

# Random suffix for unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Generate secure random passwords if not provided
resource "random_password" "gitea_admin_password" {
  count   = var.gitea_admin_password == null ? 1 : 0
  length  = 20
  special = true
  numeric = true
  upper   = true
  lower   = true
}

resource "random_password" "postgres_password" {
  count   = var.postgres_password == null ? 1 : 0
  length  = 32
  special = true
  numeric = true
  upper   = true
  lower   = true
}

# Evidence logging for compliance
resource "local_file" "deployment_evidence" {
  filename = "${path.module}/evidence/deployment_${formatdate("YYYY-MM-DD_HHmmss", timestamp())}.json"

  content = jsonencode({
    deployment_timestamp = timestamp()
    workspace           = terraform.workspace
    project_id          = var.project_id
    region              = var.region
    zone                = var.zone
    environment         = var.environment

    components_deployed = {
      compute_instance  = true
      vpc_network      = true
      firewall_rules   = true
      gcs_buckets      = true
      kms_keys         = var.enable_kms
      secret_manager   = var.enable_secret_manager
      cloud_monitoring = var.enable_monitoring
    }

    security_configuration = {
      encryption_at_rest     = var.enable_kms
      secure_boot            = var.enable_secure_boot
      shielded_vm            = var.enable_shielded_vm
      os_login               = var.enable_os_login
      vpc_service_controls   = var.enable_vpc_sc
      cloud_armor_waf        = var.enable_cloud_armor
      identity_aware_proxy   = var.enable_iap
    }

    network_configuration = {
      vpc_network          = local.network_name
      subnet               = local.subnet_name
      subnet_cidr          = var.subnet_cidr
      enable_cloud_nat     = var.enable_cloud_nat
      enable_private_google_access = true
    }

    machine_configuration = {
      machine_type     = var.machine_type
      cpu_platform     = var.cpu_platform
      boot_disk_size   = var.boot_disk_size
      boot_disk_type   = var.boot_disk_type
      data_disk_size   = var.data_disk_size
      data_disk_type   = var.data_disk_type
    }

    compliance_controls = {
      cmmc_level = "2"
      nist_800_171 = "rev-2"
      controls_implemented = [
        "AC.L2-3.1.1",  # Access Control
        "AU.L2-3.3.1",  # Audit Logging
        "IA.L2-3.5.1",  # Identification & Authentication
        "SC.L2-3.13.8", # Transmission Confidentiality
        "SC.L2-3.13.11", # Cryptographic Protection
        "CM.L2-3.4.2",  # Baseline Configuration
        "SI.L2-3.14.1", # System Monitoring
      ]
    }
  })

  lifecycle {
    create_before_destroy = false
  }
}
