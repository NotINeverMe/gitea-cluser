# Container-Optimized OS Packer Template for Docker Workloads
# CMMC 2.0: CM.L2-3.4.1, SI.L2-3.14.1
# NIST SP 800-171: 3.4.1, 3.14.1

packer {
  required_version = ">= 1.9.0"
  required_plugins {
    googlecompute = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

# Input variables
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

variable "docker_version" {
  type        = string
  description = "Docker CE version to install"
  default     = "24.0.7"
}

variable "containerd_version" {
  type        = string
  description = "Containerd version to install"
  default     = "1.7.11"
}

variable "enable_docker_bench" {
  type        = bool
  description = "Enable Docker Bench Security"
  default     = true
}

variable "enable_falco" {
  type        = bool
  description = "Enable Falco runtime security"
  default     = true
}

variable "registry_mirrors" {
  type        = list(string)
  description = "Docker registry mirrors for image pulls"
  default     = []
}

# Local variables
locals {
  timestamp    = regex_replace(timestamp(), "[- TZ:]", "")
  build_date   = timestamp()
  image_name   = "container-optimized-${local.timestamp}"

  compliance_labels = {
    "compliance-framework" = "cmmc-2-0"
    "nist-controls"       = "3-4-1_3-14-1"
    "container-runtime"   = "docker-${var.docker_version}"
    "containerd-version"  = var.containerd_version
    "build-date"         = local.timestamp
    "security-baseline"  = "cis-docker-benchmark-v1-4-0"
    "runtime-security"   = var.enable_falco ? "falco-enabled" : "falco-disabled"
  }

  docker_daemon_config = {
    "log-driver" = "json-file"
    "log-opts" = {
      "max-size" = "100m"
      "max-file" = "3"
    }
    "storage-driver" = "overlay2"
    "storage-opts" = [
      "overlay2.override_kernel_check=true"
    ]
    "live-restore" = true
    "userland-proxy" = false
    "no-new-privileges" = true
    "seccomp-profile" = "/etc/docker/seccomp-default.json"
    "icc" = false
    "disable-legacy-registry" = true
    "userns-remap" = "default"
    "registry-mirrors" = var.registry_mirrors
  }
}

# Source configuration - Container-Optimized OS
source "googlecompute" "container-optimized" {
  project_id              = var.project_id
  zone                   = var.zone
  network                = var.network
  subnetwork             = var.subnet

  # Use Ubuntu as base (COS has limited package management)
  source_image_family    = "ubuntu-2204-lts"
  source_image_project_id = ["ubuntu-os-cloud"]

  # Instance configuration
  machine_type           = "n2-standard-4"
  disk_size             = 50  # Larger disk for container images
  disk_type             = "pd-ssd"

  # SSH configuration
  ssh_username          = "packer"
  ssh_timeout          = "10m"
  ssh_clear_authorized_keys = true

  # Image metadata
  image_name            = local.image_name
  image_family         = "container-optimized"
  image_description    = "Container-optimized OS with Docker ${var.docker_version} - CMMC/NIST compliant"

  # Compliance labels
  image_labels         = local.compliance_labels

  # Storage location
  image_storage_locations = ["us"]

  # Build tags
  tags = ["packer-build", "container-optimized", "docker-hardened"]

  # Security metadata
  metadata = {
    "enable-oslogin"     = "TRUE"
    "block-project-ssh-keys" = "TRUE"
    "container-runtime"  = "docker"
  }
}

# Build configuration
build {
  name = "container-optimized-os"
  sources = ["source.googlecompute.container-optimized"]

  # System preparation
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",
      "export DEBIAN_FRONTEND=noninteractive",

      "# Wait for cloud-init",
      "cloud-init status --wait || true",

      "# Update system",
      "sudo apt-get update",
      "sudo apt-get upgrade -y",

      "# Install prerequisites",
      "sudo apt-get install -y \\",
      "  ca-certificates \\",
      "  curl \\",
      "  gnupg \\",
      "  lsb-release \\",
      "  apt-transport-https \\",
      "  software-properties-common \\",
      "  iptables \\",
      "  jq \\",
      "  git \\",
      "  make"
    ]
    pause_before = "10s"
    timeout = "10m"
  }

  # Install Docker CE with specific version
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Add Docker's official GPG key",
      "sudo mkdir -p /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",

      "# Set up repository",
      "echo \\",
      "  \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \\",
      "  $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",

      "# Install Docker packages",
      "sudo apt-get update",
      "sudo apt-get install -y \\",
      "  docker-ce=${var.docker_version}* \\",
      "  docker-ce-cli=${var.docker_version}* \\",
      "  containerd.io=${var.containerd_version}* \\",
      "  docker-buildx-plugin \\",
      "  docker-compose-plugin",

      "# Hold Docker packages to prevent auto-updates",
      "sudo apt-mark hold docker-ce docker-ce-cli containerd.io",

      "# Enable and start Docker",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
    timeout = "15m"
  }

  # Configure Docker daemon with security settings
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Create Docker daemon configuration",
      "sudo mkdir -p /etc/docker",
      "echo '${jsonencode(local.docker_daemon_config)}' | jq '.' | sudo tee /etc/docker/daemon.json",

      "# Create default seccomp profile",
      "sudo curl -L https://raw.githubusercontent.com/docker/docker-ce/master/components/engine/profiles/seccomp/default.json \\",
      "  -o /etc/docker/seccomp-default.json",

      "# Set up user namespace remapping",
      "sudo bash -c 'echo \"dockremap:165536:65536\" >> /etc/subuid'",
      "sudo bash -c 'echo \"dockremap:165536:65536\" >> /etc/subgid'",

      "# Restart Docker with new configuration",
      "sudo systemctl daemon-reload",
      "sudo systemctl restart docker"
    ]
  }

  # Install container security tools
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Install Trivy for vulnerability scanning",
      "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -",
      "echo \"deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main\" | \\",
      "  sudo tee /etc/apt/sources.list.d/trivy.list",
      "sudo apt-get update",
      "sudo apt-get install -y trivy",

      "# Install Grype for additional CVE detection",
      "curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sudo sh -s -- -b /usr/local/bin",

      "# Install Docker Bench for security auditing",
      "if [ '${var.enable_docker_bench}' = 'true' ]; then",
      "  sudo git clone https://github.com/docker/docker-bench-security.git /opt/docker-bench-security",
      "  sudo chmod +x /opt/docker-bench-security/docker-bench-security.sh",
      "fi",

      "# Install container-diff for image analysis",
      "curl -LO https://storage.googleapis.com/container-diff/latest/container-diff-linux-amd64",
      "sudo install container-diff-linux-amd64 /usr/local/bin/container-diff",
      "rm container-diff-linux-amd64"
    ]
    timeout = "20m"
  }

  # Install Falco for runtime security
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "if [ '${var.enable_falco}' = 'true' ]; then",
      "  # Add Falco repository",
      "  curl -s https://falco.org/repo/falcosecurity-3672BA8F.asc | sudo apt-key add -",
      "  echo \"deb https://download.falco.org/packages/deb stable main\" | \\",
      "    sudo tee /etc/apt/sources.list.d/falcosecurity.list",
      "  sudo apt-get update",

      "  # Install Falco",
      "  sudo apt-get install -y linux-headers-$(uname -r)",
      "  sudo apt-get install -y falco",

      "  # Configure Falco for container monitoring",
      "  sudo bash -c 'cat > /etc/falco/falco_rules.local.yaml << EOF",
      "- rule: Container Spawned Shell",
      "  desc: Detect shell spawned in container",
      "  condition: >",
      "    spawned_process and container and shell_procs",
      "  output: >",
      "    Shell spawned in container (user=%user.name container_id=%container.id)",
      "  priority: WARNING",
      "  tags: [container, shell, mitre_execution]",
      "EOF'",

      "  # Enable Falco service",
      "  sudo systemctl enable falco",
      "fi"
    ]
    timeout = "15m"
  }

  # Configure container logging and monitoring
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Install Fluent Bit for log forwarding",
      "curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh",

      "# Configure Fluent Bit for Docker logs",
      "sudo mkdir -p /etc/fluent-bit",
      "sudo bash -c 'cat > /etc/fluent-bit/fluent-bit.conf << EOF",
      "[SERVICE]",
      "    Flush         5",
      "    Daemon        off",
      "    Log_Level     info",
      "",
      "[INPUT]",
      "    Name              systemd",
      "    Tag               docker.*",
      "    Systemd_Filter    _SYSTEMD_UNIT=docker.service",
      "",
      "[INPUT]",
      "    Name              tail",
      "    Tag               containers.*",
      "    Path              /var/lib/docker/containers/*/*.log",
      "    Parser            docker",
      "    DB                /var/log/flb_docker.db",
      "    Mem_Buf_Limit     50MB",
      "",
      "[FILTER]",
      "    Name              kubernetes",
      "    Match             containers.*",
      "    Use_Journal       Off",
      "    Annotations       Off",
      "    Labels            On",
      "",
      "[OUTPUT]",
      "    Name              stdout",
      "    Match             *",
      "    Format            json_lines",
      "EOF'",

      "# Create systemd service for Fluent Bit",
      "sudo systemctl enable fluent-bit || true"
    ]
  }

  # Security hardening for containers
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Configure AppArmor profiles for Docker",
      "sudo aa-status || sudo apt-get install -y apparmor apparmor-utils",

      "# Configure SELinux policies (if applicable)",
      "sudo apt-get install -y selinux-utils || true",

      "# Set up audit rules for Docker",
      "sudo apt-get install -y auditd",
      "sudo bash -c 'cat >> /etc/audit/rules.d/docker.rules << EOF",
      "# Docker audit rules",
      "-w /usr/bin/dockerd -k docker",
      "-w /var/lib/docker -k docker",
      "-w /etc/docker -k docker",
      "-w /usr/lib/systemd/system/docker.service -k docker",
      "-w /usr/lib/systemd/system/docker.socket -k docker",
      "-w /etc/default/docker -k docker",
      "-w /etc/docker/daemon.json -k docker",
      "-w /usr/bin/containerd -k docker",
      "-w /usr/bin/runc -k docker",
      "EOF'",
      "sudo systemctl restart auditd"
    ]
  }

  # Install container scanning scripts
  provisioner "file" {
    content = <<-EOT
#!/bin/bash
# Container image security scanning script
set -euo pipefail

IMAGE_NAME=$${1:-}
if [ -z "$IMAGE_NAME" ]; then
    echo "Usage: $0 <image_name>"
    exit 1
fi

echo "=== Container Security Scan Report ==="
echo "Image: $IMAGE_NAME"
echo "Scan Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# Trivy scan
echo "=== Trivy Vulnerability Scan ==="
trivy image --severity HIGH,CRITICAL --format json "$IMAGE_NAME" > /tmp/trivy-scan.json
trivy image --severity HIGH,CRITICAL "$IMAGE_NAME"

# Grype scan
echo ""
echo "=== Grype CVE Scan ==="
grype "$IMAGE_NAME" -o json > /tmp/grype-scan.json
grype "$IMAGE_NAME"

# Docker Bench if available
if [ -x /opt/docker-bench-security/docker-bench-security.sh ]; then
    echo ""
    echo "=== Docker Bench Security ==="
    /opt/docker-bench-security/docker-bench-security.sh -l /tmp/docker-bench.log
fi

# Generate evidence
echo ""
echo "=== Generating Evidence ==="
sha256sum /tmp/*.json > /tmp/scan-evidence.sha256
echo "Evidence files generated in /tmp/"
EOT
    destination = "/tmp/container-scan.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/container-scan.sh /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/container-scan.sh"
    ]
  }

  # Generate compliance evidence
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Document installed versions",
      "docker version > /tmp/docker-version.txt",
      "containerd --version > /tmp/containerd-version.txt",
      "trivy --version > /tmp/trivy-version.txt",
      "grype version > /tmp/grype-version.txt",

      "# Document configuration",
      "docker info > /tmp/docker-info.txt",
      "cat /etc/docker/daemon.json | jq '.' > /tmp/docker-daemon-config.txt",

      "# Generate manifest",
      "sha256sum /tmp/*.txt > /tmp/container-evidence.sha256"
    ]
  }

  # Final cleanup
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euxo pipefail",

      "# Clean package cache",
      "sudo apt-get clean",
      "sudo apt-get autoremove -y",

      "# Clear logs",
      "sudo find /var/log -type f -exec truncate -s 0 {} \\;",

      "# Clear temporary files",
      "sudo rm -rf /tmp/* /var/tmp/*",

      "# Prune Docker system",
      "sudo docker system prune -af || true",

      "# Clear cloud-init",
      "sudo cloud-init clean --logs",

      "sync"
    ]
  }

  # Post-processors
  post-processor "manifest" {
    output = "manifests/container-optimized-${local.timestamp}.json"
    strip_path = true
    custom_data = {
      docker_version      = var.docker_version
      containerd_version  = var.containerd_version
      runtime_security   = var.enable_falco
      docker_bench       = var.enable_docker_bench
    }
  }
}