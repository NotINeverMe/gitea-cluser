# Hardened Ubuntu 22.04 LTS Packer Template
# CMMC 2.0: CM.L2-3.4.1 (Baseline Configuration)
# NIST SP 800-171: 3.4.1, 3.4.2 (Configuration Management)

packer {
  required_version = ">= 1.9.0"
  required_plugins {
    googlecompute = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

# Input variables for security compliance
variable "project_id" {
  type        = string
  description = "GCP Project ID for image creation"
}

variable "zone" {
  type        = string
  description = "GCP zone for image building"
  default     = "us-central1-a"
}

variable "network" {
  type        = string
  description = "GCP network for build instance"
  default     = "default"
}

variable "subnet" {
  type        = string
  description = "GCP subnet for build instance"
  default     = "default"
}

variable "image_family" {
  type        = string
  description = "Image family for organizational grouping"
  default     = "ubuntu-2204-cis-hardened"
}

variable "image_description" {
  type        = string
  description = "Description for compliance tracking"
  default     = "CIS Level 2 hardened Ubuntu 22.04 LTS - CMMC/NIST compliant"
}

variable "cis_level" {
  type        = string
  description = "CIS benchmark level (1 or 2)"
  default     = "2"
}

variable "fips_enabled" {
  type        = bool
  description = "Enable FIPS 140-2 compliant crypto modules"
  default     = true
}

variable "evidence_bucket" {
  type        = string
  description = "GCS bucket for evidence artifacts"
  default     = "gitea-compliance-evidence"
}

# Local variables for metadata
locals {
  timestamp    = regex_replace(timestamp(), "[- TZ:]", "")
  build_date   = timestamp()
  image_name   = "ubuntu-2204-cis-${local.timestamp}"

  # CMMC/NIST compliance tags
  compliance_labels = {
    "compliance-framework" = "cmmc-2-0"
    "nist-controls"       = "3-4-1_3-4-2_3-14-1"
    "cis-level"          = var.cis_level
    "fips-140-2"         = var.fips_enabled ? "enabled" : "disabled"
    "build-date"         = local.timestamp
    "security-baseline"  = "cis-ubuntu-22-04-lts-v1-0-0"
    "patch-level"        = "latest"
    "scan-status"        = "pending"
  }

  # Security metadata for evidence
  security_metadata = {
    "builder"             = "packer-${packer.version}"
    "source-image"       = "ubuntu-2204-lts"
    "hardening-script"   = "cis-hardening.sh"
    "validation-script"  = "validate-packer-images.sh"
    "evidence-location"  = "gs://${var.evidence_bucket}/${local.image_name}"
  }
}

# Source configuration - Ubuntu 22.04 LTS base
source "googlecompute" "ubuntu-cis" {
  project_id              = var.project_id
  zone                   = var.zone
  network                = var.network
  subnetwork             = var.subnet

  # Source image configuration
  source_image_family    = "ubuntu-2204-lts"
  source_image_project_id = ["ubuntu-os-cloud"]

  # Instance configuration for building
  machine_type           = "n2-standard-4"
  disk_size             = 20
  disk_type             = "pd-ssd"

  # Network security during build
  use_internal_ip       = false
  omit_external_ip      = false

  # SSH configuration with security
  ssh_username          = "packer"
  ssh_timeout          = "10m"
  ssh_handshake_attempts = 10
  ssh_clear_authorized_keys = true

  # Image metadata and naming
  image_name            = local.image_name
  image_family         = var.image_family
  image_description    = var.image_description

  # Compliance and security labels
  image_labels         = merge(
    local.compliance_labels,
    local.security_metadata
  )

  # Image encryption with CMEK (Customer-Managed Encryption Keys)
  image_encryption_key {
    kms_key_self_link = ""  # Add your KMS key here
  }

  # Storage location for compliance
  image_storage_locations = ["us"]

  # Build tags for audit
  tags = ["packer-build", "cis-hardening", "security-scan"]

  # Service account with minimal permissions
  service_account_email = ""  # Add service account with compute.imageUser role

  # Metadata for compliance tracking
  metadata = {
    "enable-oslogin"     = "TRUE"
    "block-project-ssh-keys" = "TRUE"
    "serial-port-enable" = "FALSE"
    "compliance-build"   = "true"
  }

  # Startup script for initial prep
  startup_script_file = ""

  # Shutdown behavior
  preemptible = false
  on_host_maintenance = "MIGRATE"
}

# Build configuration
build {
  name = "ubuntu-cis-hardened"
  sources = ["source.googlecompute.ubuntu-cis"]

  # Initial system update with security patches
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",
      "export DEBIAN_FRONTEND=noninteractive",

      "# Wait for cloud-init to complete",
      "cloud-init status --wait || true",

      "# Update package lists",
      "sudo apt-get update",

      "# Upgrade all packages with security patches",
      "sudo apt-get upgrade -y",

      "# Install required packages for hardening",
      "sudo apt-get install -y \\",
      "  unattended-upgrades \\",
      "  apt-listchanges \\",
      "  fail2ban \\",
      "  aide \\",
      "  auditd \\",
      "  rsyslog \\",
      "  apparmor-utils \\",
      "  libpam-pwquality \\",
      "  ufw \\",
      "  chrony \\",
      "  tcpd",

      "# Create evidence directory",
      "sudo mkdir -p /var/log/compliance-evidence",
      "sudo chmod 750 /var/log/compliance-evidence"
    ]
    pause_before = "10s"
    timeout = "10m"
  }

  # Copy CIS configuration file
  provisioner "file" {
    source      = "packer/configs/cis-level2.yaml"
    destination = "/tmp/cis-level2.yaml"
  }

  # Apply CIS hardening script
  provisioner "shell" {
    script = "packer/scripts/cis-hardening.sh"
    environment_vars = [
      "CIS_LEVEL=${var.cis_level}",
      "FIPS_ENABLED=${var.fips_enabled}",
      "BUILD_DATE=${local.build_date}",
      "IMAGE_NAME=${local.image_name}"
    ]
    timeout = "30m"
  }

  # Install security monitoring tools
  provisioner "shell" {
    script = "packer/scripts/install-security-tools.sh"
    environment_vars = [
      "INSTALL_FALCO=true",
      "INSTALL_OSQUERY=true",
      "INSTALL_WAZUH=true",
      "COMPLIANCE_MODE=true"
    ]
    timeout = "20m"
  }

  # FIPS 140-2 configuration if enabled
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "if [ '${var.fips_enabled}' = 'true' ]; then",
      "  echo 'Enabling FIPS 140-2 mode...'",
      "  sudo apt-get install -y linux-generic-hwe-22.04-fips",
      "  sudo ua enable fips || true",
      "  echo 'FIPS 140-2 mode will be active after reboot'",
      "fi"
    ]
    only = ["googlecompute.ubuntu-cis"]
  }

  # Generate compliance evidence
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Generate system inventory",
      "dpkg -l > /tmp/package-list.txt",
      "systemctl list-units --all > /tmp/services-list.txt",
      "ss -tulpn > /tmp/network-ports.txt",
      "find /etc -type f -exec sha256sum {} \\; > /tmp/config-hashes.txt",

      "# Generate compliance report",
      "echo '=== CIS Hardening Evidence ===' > /tmp/compliance-evidence.txt",
      "echo 'Build Date: ${local.build_date}' >> /tmp/compliance-evidence.txt",
      "echo 'Image Name: ${local.image_name}' >> /tmp/compliance-evidence.txt",
      "echo 'CIS Level: ${var.cis_level}' >> /tmp/compliance-evidence.txt",
      "echo 'FIPS Mode: ${var.fips_enabled}' >> /tmp/compliance-evidence.txt",
      "echo '=== System Configuration ===' >> /tmp/compliance-evidence.txt",
      "uname -a >> /tmp/compliance-evidence.txt",
      "cat /etc/os-release >> /tmp/compliance-evidence.txt",

      "# Calculate SHA-256 hashes of evidence files",
      "sha256sum /tmp/*.txt > /tmp/evidence-manifest.sha256"
    ]
  }

  # Download evidence artifacts
  provisioner "shell-local" {
    inline = [
      "mkdir -p ./evidence/${local.image_name}",
      "gcloud compute scp packer@${build.ID}:/tmp/*.txt ./evidence/${local.image_name}/ --zone=${var.zone} || true",
      "gcloud compute scp packer@${build.ID}:/tmp/*.sha256 ./evidence/${local.image_name}/ --zone=${var.zone} || true"
    ]
  }

  # Final cleanup and optimization
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Clean package cache",
      "sudo apt-get clean",
      "sudo apt-get autoremove -y",

      "# Clear logs while preserving structure",
      "sudo find /var/log -type f -exec truncate -s 0 {} \\;",

      "# Clear temporary files",
      "sudo rm -rf /tmp/* /var/tmp/*",

      "# Clear SSH host keys (will regenerate on first boot)",
      "sudo rm -f /etc/ssh/ssh_host_*",

      "# Clear machine ID (will regenerate on first boot)",
      "sudo truncate -s 0 /etc/machine-id",

      "# Clear cloud-init",
      "sudo cloud-init clean --logs",

      "# Sync filesystem",
      "sync"
    ]
  }

  # Post-processor for manifest generation
  post-processor "manifest" {
    output = "manifests/ubuntu-cis-${local.timestamp}.json"
    strip_path = true
    custom_data = {
      compliance_framework = "CMMC 2.0 / NIST SP 800-171"
      cis_level           = var.cis_level
      fips_enabled        = var.fips_enabled
      build_timestamp     = local.build_date
      evidence_location   = "gs://${var.evidence_bucket}/${local.image_name}"
    }
  }

  # Post-processor for vulnerability scanning
  post-processor "shell-local" {
    inline = [
      "echo 'Running post-build security validation...'",
      "./scripts/validate-packer-images.sh ${local.image_name} ${var.project_id} ${var.zone}"
    ]
  }
}