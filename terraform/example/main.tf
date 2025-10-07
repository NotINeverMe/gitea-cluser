# Example usage of the Gitea Stack Terraform Module
# This demonstrates how to use the module in your own Terraform configuration

terraform {
  required_version = ">= 1.5.0"
}

# Use the Gitea Stack module
module "gitea_stack" {
  source = "../gitea-stack"

  # Basic configuration
  stack_name     = "gitea-prod"
  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_email    = var.admin_email

  # Domain configuration
  gitea_domain   = var.gitea_domain
  gitea_root_url = "https://${var.gitea_domain}/"

  # Port configuration
  gitea_http_port  = 10000
  gitea_ssh_port   = 10001
  postgres_port    = 10002
  dashboard_port   = 8000

  # Enable production features
  enable_runner    = true
  enable_caddy     = true  # Enable HTTPS
  enable_dashboard = true

  # Caddy configuration for HTTPS
  caddy_https_port = 443
  caddy_http_port  = 80

  # Security settings for production
  gitea_disable_registration = true
  gitea_require_signin_view  = false
  gitea_cookie_secure        = true
  gitea_webhook_skip_tls     = false

  # Resource limits
  gitea_cpu_limit       = 4
  gitea_memory_limit    = 4096
  postgres_cpu_limit    = 2
  postgres_memory_limit = 2048
  runner_cpu_limit      = 4
  runner_memory_limit   = 8192

  # Network configuration
  network_subnet_default    = "172.20.0.0/16"
  network_subnet_data       = "172.21.0.0/16"
  network_subnet_monitoring = "172.22.0.0/16"

  # Additional labels
  additional_labels = {
    environment = "production"
    team        = "platform"
    managed_by  = "terraform"
    cost_center = "engineering"
  }
}

# Input variables
variable "admin_username" {
  description = "Gitea admin username"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Gitea admin password"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Gitea admin email"
  type        = string
}

variable "gitea_domain" {
  description = "Domain name for Gitea"
  type        = string
}

# Outputs from the module
output "gitea_url" {
  description = "Gitea web interface URL"
  value       = module.gitea_stack.gitea_url
}

output "gitea_ssh_url" {
  description = "Gitea SSH URL"
  value       = module.gitea_stack.gitea_ssh_url
}

output "dashboard_url" {
  description = "DevSecOps dashboard URL"
  value       = module.gitea_stack.dashboard_url
}

output "admin_username" {
  description = "Gitea admin username"
  value       = module.gitea_stack.admin_username
}

output "health_check_urls" {
  description = "URLs for health checking"
  value       = module.gitea_stack.health_check_urls
}

output "first_time_setup" {
  description = "First-time setup instructions"
  value       = module.gitea_stack.first_time_setup
}