# Compute Engine Instance for Gitea GCP Deployment
# CMMC 2.0 Level 2 Compliant Compute Configuration
# NIST SP 800-171 Rev. 2 Security Controls

# ============================================================================
# COMPUTE ENGINE INSTANCE - CM.L2-3.4.2: System Baseline Configuration
# ============================================================================

resource "google_compute_instance" "gitea_server" {
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  # Enable deletion protection for production
  deletion_protection = false  # Temporarily disabled to allow instance replacement

  # Minimum CPU platform not supported for e2-standard-8
  # min_cpu_platform = var.cpu_platform

  # Tags for firewall rules and identification
  tags = ["gitea-server", "https-server", "ssh-server"]

  # Labels for CMMC asset categorization - AC.L2-3.1.1: Authorized Access
  labels = local.cmmc_labels.gitea_vm

  # Boot disk configuration - SC.L2-3.13.11: Cryptographic Protection
  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_size
      type  = var.boot_disk_type

      # Labels for the boot disk
      labels = merge(local.common_labels, {
        "disk-type" = "boot"
        "encrypted" = "true"
      })
    }

    # Enable CMEK encryption if KMS is enabled
    # Note: Disk encryption configured via disk_encryption_key at attached_disk level
    # dynamic "disk_encryption_key" {
    #   for_each = var.enable_kms ? [1] : []
    #   content {
    #     kms_key_self_link = google_kms_crypto_key.disk_key[0].id
    #   }
    # }

    # Auto-delete boot disk when instance is deleted
    auto_delete = true

    # DeviceBook name
    device_name = "gitea-boot"
  }

  # Additional data disk for Docker volumes - SC.L2-3.13.16: Data at Rest
  attached_disk {
    source      = google_compute_disk.gitea_data.self_link
    device_name = "gitea-data"
    mode        = "READ_WRITE"
  }

  # Network configuration - SC.L2-3.13.5: Publicly Accessible Systems
  network_interface {
    network    = google_compute_network.gitea_network.id
    subnetwork = google_compute_subnetwork.gitea_subnet.id

    # Assign external IP for public access
    access_config {
      nat_ip       = google_compute_address.gitea_ip.address
      network_tier = "PREMIUM"
    }
  }

  # Service account with least privilege - AC.L2-3.1.5: Least Privilege
  service_account {
    email = google_service_account.gitea_sa.email
    scopes = [
      "cloud-platform", # Required for full GCP API access
    ]
  }

  # Shielded VM configuration - SC.L2-3.13.15: System Integrity
  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                 = var.enable_vtpm
    enable_integrity_monitoring = var.enable_integrity_monitoring
  }

  # Metadata for instance configuration
  metadata = merge(
    {
      # Enable OS Login for centralized SSH key management - IA.L2-3.5.1
      "enable-oslogin" = var.enable_os_login ? "TRUE" : "FALSE"

      # Block project-wide SSH keys for security
      "block-project-ssh-keys" = "TRUE"

      # Startup script
      "startup-script" = templatefile("${path.module}/startup-script.sh", {
        project_id              = var.project_id
        region                  = var.region
        zone                    = var.zone
        environment             = var.environment
        gitea_domain           = var.gitea_domain
        gitea_admin_username   = var.gitea_admin_username
        gitea_admin_email      = var.gitea_admin_email
        admin_password_secret  = local.admin_password_secret
        db_password_secret     = local.db_password_secret
        runner_token_secret    = local.runner_token_secret
        evidence_bucket        = "${local.evidence_bucket}-${random_id.bucket_suffix.hex}"
        backup_bucket          = "${local.backup_bucket}-${random_id.bucket_suffix.hex}"
        logs_bucket            = "${local.logs_bucket}-${random_id.bucket_suffix.hex}"
        enable_secret_manager  = var.enable_secret_manager
        custom_startup_script  = var.custom_startup_script
        gitea_disable_registration = var.gitea_disable_registration
        gitea_require_signin_view = var.gitea_require_signin_view
        enable_docker_gcr      = var.enable_docker_gcr
        distro_id              = "Ubuntu"
        distro_codename        = "jammy"
      })

      # Serial port logging for debugging
      "serial-port-enable" = "TRUE"
    },
    var.metadata
  )

  # Use only one startup script mechanism. The full bootstrap runs via
  # metadata["startup-script"] above to avoid conflicts with
  # metadata_startup_script.

  # Scheduling for cost optimization and maintenance windows
  scheduling {
    preemptible       = false
    automatic_restart = true
    on_host_maintenance = "MIGRATE"

    # Node affinity commented out - cannot specify both cpu_platform and node_affinities
    # node_affinities {
    #   key      = "node-group"
    #   operator = "IN"
    #   values   = ["gitea-nodes"]
    # }
  }

  # Guest accelerators (if needed for ML workloads)
  # guest_accelerator {
  #   type  = "nvidia-tesla-t4"
  #   count = 0
  # }

  # Enable display for debugging (disabled in production)
  enable_display = false

  # Confidential compute (if supported by machine type)
  confidential_instance_config {
    enable_confidential_compute = false
  }

  # Advanced machine features
  advanced_machine_features {
    enable_nested_virtualization = false
    threads_per_core            = 2
  }

  lifecycle {
    # Prevent accidental deletion
    prevent_destroy = false

    # Ignore changes to metadata that might be updated by startup scripts
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }

  depends_on = [
    google_compute_network.gitea_network,
    google_compute_subnetwork.gitea_subnet,
    google_service_account.gitea_sa,
    google_compute_disk.gitea_data,
  ]
}

# ============================================================================
# PERSISTENT DISK FOR DATA - SC.L2-3.13.16: Information at Rest
# ============================================================================

resource "google_compute_disk" "gitea_data" {
  name  = "${local.instance_name}-data"
  type  = var.data_disk_type
  zone  = var.zone
  size  = var.data_disk_size

  # Physical block size for better performance
  physical_block_size_bytes = 4096

  # Labels for identification
  labels = merge(local.common_labels, {
    "disk-type" = "data"
    "encrypted" = "true"
    "purpose"   = "docker-volumes"
  })

  # Enable CMEK encryption if KMS is enabled
  dynamic "disk_encryption_key" {
    for_each = var.enable_kms ? [1] : []
    content {
      kms_key_self_link = google_kms_crypto_key.disk_key[0].id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# ============================================================================
# INSTANCE GROUP FOR LOAD BALANCING (OPTIONAL)
# ============================================================================

resource "google_compute_instance_group" "gitea_group" {
  name        = "${local.name_prefix}-instance-group"
  zone        = var.zone
  description = "Instance group for Gitea server"

  instances = [
    google_compute_instance.gitea_server.id
  ]

  named_port {
    name = "https"
    port = "443"
  }

  named_port {
    name = "http"
    port = "80"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# SNAPSHOT SCHEDULE FOR BACKUPS - CP.L2-3.11.1: System Backup
# ============================================================================

resource "google_compute_resource_policy" "daily_backup" {
  name   = "${local.name_prefix}-daily-backup"
  region = var.region

  description = "Daily backup schedule for Gitea disks - CP.L2-3.11.1"

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "02:00"
      }
    }

    retention_policy {
      max_retention_days    = var.backup_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels = merge(local.common_labels, {
        "backup-type" = "scheduled"
        "retention"   = "${var.backup_retention_days}-days"
      })

      storage_locations = [var.region]
      guest_flush       = false
    }
  }
}

# Attach backup policy to boot disk
resource "google_compute_disk_resource_policy_attachment" "boot_backup" {
  name = google_compute_resource_policy.daily_backup.name
  disk = google_compute_instance.gitea_server.name
  zone = var.zone
}

# Attach backup policy to data disk
resource "google_compute_disk_resource_policy_attachment" "data_backup" {
  name = google_compute_resource_policy.daily_backup.name
  disk = google_compute_disk.gitea_data.name
  zone = var.zone
}

# ============================================================================
# INSTANCE TEMPLATE (FOR FUTURE SCALING)
# ============================================================================

resource "google_compute_instance_template" "gitea_template" {
  count = 0  # Disabled by default, enable for autoscaling

  name_prefix  = "${local.name_prefix}-template-"
  machine_type = var.machine_type
  region       = var.region

  # Use the same configuration as the main instance
  tags   = ["gitea-server", "https-server", "ssh-server"]
  labels = local.cmmc_labels.gitea_vm

  disk {
    source_image = data.google_compute_image.ubuntu.self_link
    boot         = true
    disk_size_gb = var.boot_disk_size
    disk_type    = var.boot_disk_type

    dynamic "disk_encryption_key" {
      for_each = var.enable_kms ? [1] : []
      content {
        kms_key_self_link = google_kms_crypto_key.disk_key[0].id
      }
    }
  }

  network_interface {
    network    = google_compute_network.gitea_network.id
    subnetwork = google_compute_subnetwork.gitea_subnet.id

    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.gitea_sa.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                 = var.enable_vtpm
    enable_integrity_monitoring = var.enable_integrity_monitoring
  }

  lifecycle {
    create_before_destroy = true
  }
}
