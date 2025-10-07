# PostgreSQL Database Container for Gitea

# Pull PostgreSQL image
resource "docker_image" "postgres" {
  name         = var.postgres_image
  keep_locally = true
}

# PostgreSQL container
resource "docker_container" "postgres_gitea" {
  name  = "postgres-${var.stack_name}"
  image = docker_image.postgres.image_id

  restart = "unless-stopped"

  # Environment variables
  env = [
    "POSTGRES_DB=${var.postgres_database}",
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_PASSWORD=${local.postgres_password}",
    "PGDATA=/var/lib/postgresql/data/pgdata"
  ]

  # Port mapping
  ports {
    internal = 5432
    external = var.postgres_port
    ip       = "0.0.0.0"
  }

  # Volume mounts
  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  dynamic "volumes" {
    for_each = var.backup_path != "" ? [1] : []
    content {
      host_path      = var.backup_path
      container_path = "/backups"
    }
  }

  # Network attachments
  networks_advanced {
    name = docker_network.gitea_data.name
  }

  networks_advanced {
    name = docker_network.gitea_default.name
  }

  networks_advanced {
    name = docker_network.gitea_monitoring.name
  }

  # Health check
  healthcheck {
    test = ["CMD-SHELL", "pg_isready -U ${var.postgres_user} -d ${var.postgres_database}"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
    start_period = "30s"
  }

  # Resource limits
  cpu_limit    = var.postgres_cpu_limit * 1000  # Convert to millicores
  memory       = var.postgres_memory_limit      # In MB
  memory_swap  = var.postgres_memory_limit      # Same as memory to disable swap

  # Labels
  dynamic "labels" {
    for_each = local.stack_labels.database
    content {
      label = labels.key
      value = labels.value
    }
  }

  # Ensure proper cleanup
  must_run = true

  lifecycle {
    ignore_changes = [
      env,  # Ignore password changes to prevent recreation
    ]
  }

  # Log configuration
  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
}

# Store database connection info in a local file for reference
resource "local_sensitive_file" "postgres_connection" {
  filename = "${path.module}/.postgres_connection.json"

  content = jsonencode({
    host     = "localhost"
    port     = var.postgres_port
    database = var.postgres_database
    user     = var.postgres_user
    password = local.postgres_password

    internal_connection = {
      host = docker_container.postgres_gitea.name
      port = 5432
    }
  })

  file_permission = "0600"
}