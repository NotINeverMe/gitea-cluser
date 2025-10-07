# Outputs for Gitea Docker Stack

# URLs and endpoints
output "gitea_url" {
  description = "URL to access Gitea web interface"
  value       = local.gitea_root_url
}

output "gitea_ssh_url" {
  description = "SSH URL for Git operations"
  value       = "ssh://git@${var.gitea_domain}:${var.gitea_ssh_port}"
}

output "dashboard_url" {
  description = "URL to access DevSecOps dashboard"
  value       = var.enable_dashboard ? "http://localhost:${var.dashboard_port}" : null
}

output "caddy_https_url" {
  description = "HTTPS URL via Caddy reverse proxy"
  value       = var.enable_caddy ? "https://${var.gitea_domain}:${var.caddy_https_port}" : null
}

# Admin credentials
output "admin_username" {
  description = "Gitea admin username"
  value       = var.admin_username
}

output "admin_credentials_file" {
  description = "Path to file containing admin credentials"
  value       = local_sensitive_file.gitea_admin_credentials.filename
  sensitive   = true
}

# Container information
output "container_ids" {
  description = "Container IDs for all deployed services"
  value = {
    postgres  = docker_container.postgres_gitea.id
    gitea     = docker_container.gitea.id
    runner    = var.enable_runner ? docker_container.gitea_runner[0].id : null
    caddy     = var.enable_caddy ? docker_container.caddy_gitea[0].id : null
    dashboard = var.enable_dashboard ? docker_container.dashboard[0].id : null
  }
}

output "container_names" {
  description = "Container names for all deployed services"
  value = {
    postgres  = docker_container.postgres_gitea.name
    gitea     = docker_container.gitea.name
    runner    = var.enable_runner ? docker_container.gitea_runner[0].name : null
    caddy     = var.enable_caddy ? docker_container.caddy_gitea[0].name : null
    dashboard = var.enable_dashboard ? docker_container.dashboard[0].name : null
  }
}

# Network information
output "network_ids" {
  description = "Docker network IDs"
  value = {
    default    = docker_network.gitea_default.id
    data       = docker_network.gitea_data.id
    monitoring = docker_network.gitea_monitoring.id
  }
}

output "network_names" {
  description = "Docker network names"
  value = {
    default    = docker_network.gitea_default.name
    data       = docker_network.gitea_data.name
    monitoring = docker_network.gitea_monitoring.name
  }
}

# Volume information
output "volume_names" {
  description = "Docker volume names"
  value = {
    gitea_data    = docker_volume.gitea_data.name
    gitea_config  = docker_volume.gitea_config.name
    postgres_data = docker_volume.postgres_data.name
    actions_cache = docker_volume.actions_cache.name
    caddy_data    = var.enable_caddy ? docker_volume.caddy_data[0].name : null
    caddy_config  = var.enable_caddy ? docker_volume.caddy_config[0].name : null
  }
}

# Database connection
output "postgres_connection" {
  description = "PostgreSQL connection information"
  value = {
    host     = "localhost"
    port     = var.postgres_port
    database = var.postgres_database
    user     = var.postgres_user
  }
  sensitive = true
}

# API and metrics endpoints
output "api_endpoints" {
  description = "API endpoints for Gitea"
  value = {
    health  = "${local.gitea_root_url}api/healthz"
    swagger = "${local.gitea_root_url}api/swagger"
    v1      = "${local.gitea_root_url}api/v1"
  }
}

output "metrics_endpoint" {
  description = "Prometheus metrics endpoint"
  value       = "${local.gitea_root_url}metrics"
}

output "metrics_token" {
  description = "Token for accessing metrics endpoint"
  value       = local.gitea_metrics_token
  sensitive   = true
}

# Stack information
output "stack_name" {
  description = "Name of the deployed stack"
  value       = var.stack_name
}

output "workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

# Component status
output "components_enabled" {
  description = "Status of optional components"
  value = {
    runner    = var.enable_runner
    caddy     = var.enable_caddy
    dashboard = var.enable_dashboard
  }
}

# Security configuration
output "security_config" {
  description = "Security configuration summary"
  value = {
    rootless_deployment   = var.gitea_rootless
    registration_disabled = var.gitea_disable_registration
    secure_cookies       = var.gitea_cookie_secure
    password_complexity  = "lower,upper,digit,spec"
    min_password_length  = 14
    password_hash_algo   = "argon2"
    oauth2_enabled      = true
    metrics_enabled     = true
  }
}

# Evidence log
output "evidence_log_file" {
  description = "Path to deployment evidence log file"
  value       = local_file.deployment_evidence.filename
}

# Health check URLs
output "health_check_urls" {
  description = "URLs for health checking services"
  value = {
    gitea     = "${local.gitea_root_url}api/healthz"
    dashboard = var.enable_dashboard ? "http://localhost:${var.dashboard_port}/health" : null
  }
}

# Instructions
output "first_time_setup" {
  description = "First-time setup instructions"
  value = <<-EOT
    Gitea Stack Deployment Complete!

    1. Access Gitea: ${local.gitea_root_url}
       Admin Login: ${var.admin_username}

    2. SSH Git URL: ssh://git@${var.gitea_domain}:${var.gitea_ssh_port}/<username>/<repo>.git

    3. Additional Services:
       ${var.enable_dashboard ? "- Dashboard: http://localhost:${var.dashboard_port}" : ""}
       ${var.enable_caddy ? "- HTTPS: https://${var.gitea_domain}:${var.caddy_https_port}" : ""}

    4. To configure Actions Runner:
       - Go to Admin -> Runners
       - Generate a registration token
       - Update the runner configuration

    5. Check service health:
       - docker ps --filter "label=com.devsecops.stack=${var.stack_name}"
       - curl ${local.gitea_root_url}api/healthz

    Admin credentials are stored in: ${local_sensitive_file.gitea_admin_credentials.filename}
  EOT
}