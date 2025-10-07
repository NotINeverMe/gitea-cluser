# Docker Volumes for Gitea Stack

# Gitea data volume
resource "docker_volume" "gitea_data" {
  name = local.volume_names.gitea_data

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.volume.type"
    value = "gitea-data"
  }

  labels {
    label = "com.devsecops.managed-by"
    value = "terraform"
  }

  labels {
    label = "com.devsecops.environment"
    value = terraform.workspace
  }

  labels {
    label = "com.cmmc.asset-category"
    value = "CUI"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Gitea configuration volume
resource "docker_volume" "gitea_config" {
  name = local.volume_names.gitea_config

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.volume.type"
    value = "gitea-config"
  }

  labels {
    label = "com.devsecops.managed-by"
    value = "terraform"
  }

  labels {
    label = "com.devsecops.environment"
    value = terraform.workspace
  }

  labels {
    label = "com.cmmc.asset-category"
    value = "SPA"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# PostgreSQL data volume
resource "docker_volume" "postgres_data" {
  name = local.volume_names.postgres_data

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.volume.type"
    value = "postgres-data"
  }

  labels {
    label = "com.devsecops.managed-by"
    value = "terraform"
  }

  labels {
    label = "com.devsecops.environment"
    value = terraform.workspace
  }

  labels {
    label = "com.cmmc.asset-category"
    value = "CUI"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Gitea Actions cache volume
resource "docker_volume" "actions_cache" {
  name = local.volume_names.actions_cache

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.volume.type"
    value = "actions-cache"
  }

  labels {
    label = "com.devsecops.managed-by"
    value = "terraform"
  }

  labels {
    label = "com.devsecops.environment"
    value = terraform.workspace
  }

  labels {
    label = "com.cmmc.asset-category"
    value = "SPC"
  }
}

# Caddy data volume (conditional)
resource "docker_volume" "caddy_data" {
  count = var.enable_caddy ? 1 : 0
  name  = local.volume_names.caddy_data

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.volume.type"
    value = "caddy-data"
  }

  labels {
    label = "com.devsecops.managed-by"
    value = "terraform"
  }

  labels {
    label = "com.devsecops.environment"
    value = terraform.workspace
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Caddy config volume (conditional)
resource "docker_volume" "caddy_config" {
  count = var.enable_caddy ? 1 : 0
  name  = local.volume_names.caddy_config

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.volume.type"
    value = "caddy-config"
  }

  labels {
    label = "com.devsecops.managed-by"
    value = "terraform"
  }

  labels {
    label = "com.devsecops.environment"
    value = terraform.workspace
  }

  lifecycle {
    prevent_destroy = true
  }
}