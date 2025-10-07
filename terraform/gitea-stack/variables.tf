# Variables for Gitea Docker Stack Terraform Module

# Docker configuration
variable "docker_host" {
  description = "Docker host URL"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

# Stack configuration
variable "stack_name" {
  description = "Name of the stack for resource labeling"
  type        = string
  default     = "gitea"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.stack_name))
    error_message = "Stack name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens"
  }
}

# Admin credentials
variable "admin_username" {
  description = "Gitea admin username"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.admin_username) >= 3 && length(var.admin_username) <= 40
    error_message = "Admin username must be between 3 and 40 characters"
  }
}

variable "admin_password" {
  description = "Gitea admin password (minimum 14 characters, requires upper, lower, digit, special)"
  type        = string
  sensitive   = true

  validation {
    condition = can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>/?]).{14,}$", var.admin_password))
    error_message = "Admin password must be at least 14 characters and contain uppercase, lowercase, digit, and special character"
  }
}

variable "admin_email" {
  description = "Gitea admin email address"
  type        = string
  default     = "admin@example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Must be a valid email address"
  }
}

# Port configuration
variable "gitea_http_port" {
  description = "HTTP port for Gitea web interface"
  type        = number
  default     = 10000

  validation {
    condition     = var.gitea_http_port >= 1024 && var.gitea_http_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

variable "gitea_ssh_port" {
  description = "SSH port for Git operations"
  type        = number
  default     = 10001

  validation {
    condition     = var.gitea_ssh_port >= 1024 && var.gitea_ssh_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

variable "postgres_port" {
  description = "PostgreSQL database port"
  type        = number
  default     = 10002

  validation {
    condition     = var.postgres_port >= 1024 && var.postgres_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

variable "caddy_https_port" {
  description = "HTTPS port for Caddy reverse proxy"
  type        = number
  default     = 10003

  validation {
    condition     = var.caddy_https_port >= 1024 && var.caddy_https_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

variable "caddy_http_port" {
  description = "HTTP port for Caddy reverse proxy (redirects to HTTPS)"
  type        = number
  default     = 10004

  validation {
    condition     = var.caddy_http_port >= 1024 && var.caddy_http_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

variable "dashboard_port" {
  description = "Port for DevSecOps dashboard"
  type        = number
  default     = 8000

  validation {
    condition     = var.dashboard_port >= 1024 && var.dashboard_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

# Database configuration
variable "postgres_password" {
  description = "PostgreSQL database password (auto-generated if not provided)"
  type        = string
  sensitive   = true
  default     = null
}

variable "postgres_database" {
  description = "PostgreSQL database name"
  type        = string
  default     = "gitea"
}

variable "postgres_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "gitea"
}

# Security tokens
variable "gitea_secret_key" {
  description = "Gitea secret key for session encryption (auto-generated if not provided)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitea_internal_token" {
  description = "Gitea internal token for service communication (auto-generated if not provided)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitea_oauth2_jwt_secret" {
  description = "OAuth2 JWT secret (auto-generated if not provided)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitea_metrics_token" {
  description = "Token for accessing Prometheus metrics endpoint (auto-generated if not provided)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitea_runner_token" {
  description = "Registration token for Gitea Actions runner"
  type        = string
  sensitive   = true
  default     = ""
}

# Domain configuration
variable "gitea_domain" {
  description = "Domain name for Gitea instance"
  type        = string
  default     = "localhost"
}

variable "gitea_root_url" {
  description = "Root URL for Gitea instance"
  type        = string
  default     = ""
}

# Component toggles
variable "enable_runner" {
  description = "Enable Gitea Actions runner"
  type        = bool
  default     = true
}

variable "enable_caddy" {
  description = "Enable Caddy reverse proxy for TLS termination"
  type        = bool
  default     = false
}

variable "enable_dashboard" {
  description = "Enable DevSecOps dashboard"
  type        = bool
  default     = true
}

# Image versions
variable "postgres_image" {
  description = "PostgreSQL Docker image"
  type        = string
  default     = "postgres:15-alpine"
}

variable "gitea_image" {
  description = "Gitea Docker image"
  type        = string
  default     = "gitea/gitea:1.21-rootless"
}

variable "runner_image" {
  description = "Gitea Actions runner Docker image"
  type        = string
  default     = "gitea/act_runner:latest"
}

variable "caddy_image" {
  description = "Caddy Docker image"
  type        = string
  default     = "caddy:2-alpine"
}

variable "dashboard_image" {
  description = "DevSecOps dashboard Docker image"
  type        = string
  default     = "devsecops-dashboard:latest"
}

# Resource limits - PostgreSQL
variable "postgres_cpu_limit" {
  description = "CPU limit for PostgreSQL container (in CPU units)"
  type        = number
  default     = 2
}

variable "postgres_memory_limit" {
  description = "Memory limit for PostgreSQL container (in MB)"
  type        = number
  default     = 2048
}

# Resource limits - Gitea
variable "gitea_cpu_limit" {
  description = "CPU limit for Gitea container (in CPU units)"
  type        = number
  default     = 4
}

variable "gitea_memory_limit" {
  description = "Memory limit for Gitea container (in MB)"
  type        = number
  default     = 4096
}

# Resource limits - Runner
variable "runner_cpu_limit" {
  description = "CPU limit for Gitea runner container (in CPU units)"
  type        = number
  default     = 4
}

variable "runner_memory_limit" {
  description = "Memory limit for Gitea runner container (in MB)"
  type        = number
  default     = 8192
}

# Gitea configuration
variable "gitea_disable_registration" {
  description = "Disable user self-registration"
  type        = bool
  default     = false
}

variable "gitea_require_signin_view" {
  description = "Require sign-in to view any content"
  type        = bool
  default     = false
}

variable "gitea_cookie_secure" {
  description = "Use secure cookies (requires HTTPS)"
  type        = bool
  default     = false
}

variable "gitea_webhook_skip_tls" {
  description = "Skip TLS verification for webhooks"
  type        = bool
  default     = false
}

# Deployment mode
variable "gitea_rootless" {
  description = "Deploy Gitea in rootless mode"
  type        = bool
  default     = true
}

variable "gitea_user_uid" {
  description = "User UID for rootless Gitea"
  type        = number
  default     = 1000
}

variable "gitea_user_gid" {
  description = "User GID for rootless Gitea"
  type        = number
  default     = 1000
}

# File paths
variable "caddyfile_path" {
  description = "Path to Caddyfile for reverse proxy configuration"
  type        = string
  default     = ""
}

variable "runner_config_path" {
  description = "Path to runner configuration file"
  type        = string
  default     = ""
}

# Backup configuration
variable "backup_path" {
  description = "Host path for database backups"
  type        = string
  default     = ""
}

# Additional labels
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# Network configuration
variable "network_subnet_default" {
  description = "Subnet for default network"
  type        = string
  default     = "172.20.0.0/16"
}

variable "network_subnet_data" {
  description = "Subnet for data network (internal)"
  type        = string
  default     = "172.21.0.0/16"
}

variable "network_subnet_monitoring" {
  description = "Subnet for monitoring network"
  type        = string
  default     = "172.22.0.0/16"
}