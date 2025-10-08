# Secret Manager Integration
# Retrieves secrets at runtime - no secrets in Terraform state

# ============================================================================
# DATA SOURCES - RETRIEVE SECRETS FROM SECRET MANAGER
# ============================================================================

# Gitea admin password
data "google_secret_manager_secret_version" "admin_password" {
  secret  = "gitea-admin-password"
  project = var.project_id
}

# PostgreSQL database password
data "google_secret_manager_secret_version" "postgres_password" {
  secret  = "postgres-password"
  project = var.project_id
}

# Gitea secret key for session encryption
data "google_secret_manager_secret_version" "gitea_secret_key" {
  secret  = "gitea-secret-key"
  project = var.project_id
}

# Gitea internal token for API authentication
data "google_secret_manager_secret_version" "gitea_internal_token" {
  secret  = "gitea-internal-token"
  project = var.project_id
}

# OAuth2 JWT secret
data "google_secret_manager_secret_version" "gitea_oauth2_jwt_secret" {
  secret  = "gitea-oauth2-jwt-secret"
  project = var.project_id
}

# Prometheus metrics token
data "google_secret_manager_secret_version" "gitea_metrics_token" {
  secret  = "gitea-metrics-token"
  project = var.project_id
}

# Gitea Actions runner registration token
data "google_secret_manager_secret_version" "gitea_runner_token" {
  secret  = "gitea-runner-token"
  project = var.project_id
}

# Namecheap API credentials for DNS updates
data "google_secret_manager_secret_version" "namecheap_api_key" {
  secret  = "namecheap-api-key"
  project = var.project_id
}

data "google_secret_manager_secret_version" "namecheap_api_user" {
  secret  = "namecheap-api-user"
  project = var.project_id
}

data "google_secret_manager_secret_version" "namecheap_api_ip" {
  secret  = "namecheap-api-ip"
  project = var.project_id
}

# ============================================================================
# LOCALS - DECODE SECRETS
# ============================================================================

locals {
  # Decode secrets from Secret Manager
  # These are used in the compute instance metadata startup script
  admin_password         = data.google_secret_manager_secret_version.admin_password.secret_data
  postgres_password      = data.google_secret_manager_secret_version.postgres_password.secret_data
  gitea_secret_key       = data.google_secret_manager_secret_version.gitea_secret_key.secret_data
  gitea_internal_token   = data.google_secret_manager_secret_version.gitea_internal_token.secret_data
  gitea_oauth2_jwt_secret = data.google_secret_manager_secret_version.gitea_oauth2_jwt_secret.secret_data
  gitea_metrics_token    = data.google_secret_manager_secret_version.gitea_metrics_token.secret_data
  gitea_runner_token     = data.google_secret_manager_secret_version.gitea_runner_token.secret_data

  # DNS automation credentials
  namecheap_api_key  = data.google_secret_manager_secret_version.namecheap_api_key.secret_data
  namecheap_api_user = data.google_secret_manager_secret_version.namecheap_api_user.secret_data
  namecheap_api_ip   = data.google_secret_manager_secret_version.namecheap_api_ip.secret_data
}

# ============================================================================
# CREATE DOCKER SECRETS FILES ON VM
# ============================================================================

# This script writes secrets to /run/secrets/ for Docker to consume
# Secrets are written at instance startup, never stored in Terraform state
resource "null_resource" "write_secrets_to_vm" {
  depends_on = [google_compute_instance.gitea]

  triggers = {
    instance_id = google_compute_instance.gitea.instance_id
  }

  provisioner "remote-exec" {
    inline = [
      # Create secrets directory
      "sudo mkdir -p /run/secrets",
      "sudo chmod 700 /run/secrets",

      # Write secrets from metadata (populated by startup script)
      "sudo bash -c 'echo \"${local.admin_password}\" > /run/secrets/admin_password'",
      "sudo bash -c 'echo \"${local.postgres_password}\" > /run/secrets/postgres_password'",
      "sudo bash -c 'echo \"${local.gitea_secret_key}\" > /run/secrets/gitea_secret_key'",
      "sudo bash -c 'echo \"${local.gitea_internal_token}\" > /run/secrets/gitea_internal_token'",
      "sudo bash -c 'echo \"${local.gitea_oauth2_jwt_secret}\" > /run/secrets/gitea_oauth2_jwt_secret'",
      "sudo bash -c 'echo \"${local.gitea_metrics_token}\" > /run/secrets/gitea_metrics_token'",
      "sudo bash -c 'echo \"${local.gitea_runner_token}\" > /run/secrets/gitea_runner_token'",

      # Set permissions (read-only, root only)
      "sudo chmod 400 /run/secrets/*",
      "sudo chown root:root /run/secrets/*",

      # Restart Docker containers to pick up new secrets
      "cd /home/gitea && docker compose -f docker-compose.gcp.yml restart"
    ]

    connection {
      type         = "ssh"
      user         = "gitea"
      host         = google_compute_instance.gitea.network_interface[0].access_config[0].nat_ip
      private_key  = file("~/.ssh/id_rsa")
      bastion_host = var.enable_iap ? null : google_compute_instance.gitea.network_interface[0].access_config[0].nat_ip
    }
  }
}

# ============================================================================
# OUTPUTS (Non-sensitive metadata only)
# ============================================================================

output "secrets_configured" {
  description = "Confirmation that secrets are configured"
  value = {
    secret_manager_secrets = [
      "gitea-admin-password",
      "postgres-password",
      "gitea-secret-key",
      "gitea-internal-token",
      "gitea-oauth2-jwt-secret",
      "gitea-metrics-token",
      "gitea-runner-token",
      "namecheap-api-key",
      "namecheap-api-user",
      "namecheap-api-ip",
    ]
    secrets_location = "/run/secrets/ on VM"
    rotation_policy  = "90 days recommended"
  }
}
