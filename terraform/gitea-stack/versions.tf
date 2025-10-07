# Provider and version requirements for Gitea Docker stack
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Docker provider configuration
provider "docker" {
  host = var.docker_host
}

# Generate secure random values if not provided
resource "random_password" "gitea_secret_key" {
  count   = var.gitea_secret_key == null ? 1 : 0
  length  = 64
  special = true
}

resource "random_password" "gitea_internal_token" {
  count   = var.gitea_internal_token == null ? 1 : 0
  length  = 128
  special = false
}

resource "random_password" "gitea_oauth2_jwt_secret" {
  count   = var.gitea_oauth2_jwt_secret == null ? 1 : 0
  length  = 44
  special = false
}

resource "random_password" "postgres_password" {
  count   = var.postgres_password == null ? 1 : 0
  length  = 32
  special = true
  override_special = "!@#$%^&*()_+-="
}

resource "random_password" "gitea_metrics_token" {
  count   = var.gitea_metrics_token == null ? 1 : 0
  length  = 32
  special = false
}