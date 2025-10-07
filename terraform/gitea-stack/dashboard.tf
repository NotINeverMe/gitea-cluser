# DevSecOps Dashboard Container

# Pull dashboard image (conditional)
resource "docker_image" "dashboard" {
  count        = var.enable_dashboard ? 1 : 0
  name         = var.dashboard_image
  keep_locally = true
}

# DevSecOps Dashboard container (conditional)
resource "docker_container" "dashboard" {
  count = var.enable_dashboard ? 1 : 0
  name  = "dashboard-${var.stack_name}"
  image = docker_image.dashboard[0].image_id

  restart = "unless-stopped"

  # Run as root for Docker socket access
  user = "root"

  # Environment variables
  env = [
    "DASHBOARD_PORT=${var.dashboard_port}",
    "GITEA_URL=http://${docker_container.gitea.name}:${var.gitea_http_port}",
    "GITEA_ADMIN_USER=${var.admin_username}",
    "POSTGRES_HOST=${docker_container.postgres_gitea.name}",
    "POSTGRES_PORT=5432",
    "POSTGRES_DB=${var.postgres_database}",
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_PASSWORD=${local.postgres_password}",
    "STACK_NAME=${var.stack_name}",
    "METRICS_ENABLED=true",
    "METRICS_TOKEN=${local.gitea_metrics_token}",
    "TZ=UTC"
  ]

  # Port mapping
  ports {
    internal = var.dashboard_port
    external = var.dashboard_port
    ip       = "0.0.0.0"
  }

  # Volume mounts
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  # Network attachments
  networks_advanced {
    name = docker_network.gitea_default.name
  }

  networks_advanced {
    name = docker_network.gitea_monitoring.name
  }

  # Health check
  healthcheck {
    test = ["CMD-SHELL", "curl -f http://localhost:${var.dashboard_port}/health || exit 1"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
    start_period = "30s"
  }

  # Resource limits
  cpu_limit    = 2000     # 2 CPU cores
  memory       = 1024     # 1GB memory
  memory_swap  = 1024     # Same as memory to disable swap

  # Labels
  dynamic "labels" {
    for_each = local.stack_labels.dashboard
    content {
      label = labels.key
      value = labels.value
    }
  }

  # Additional monitoring labels
  labels {
    label = "com.devsecops.monitor.enabled"
    value = "true"
  }

  labels {
    label = "com.devsecops.monitor.endpoints"
    value = "/health,/metrics,/api/status"
  }

  # Dependencies
  depends_on = [
    docker_container.gitea,
    docker_container.postgres_gitea,
    docker_network.gitea_default,
    docker_network.gitea_monitoring
  ]

  # Ensure proper cleanup
  must_run = true

  # Log configuration
  log_driver = "json-file"
  log_opts = {
    "max-size" = "20m"
    "max-file" = "3"
    "labels"   = "com.devsecops.stack,com.devsecops.category"
    "tag"      = "dashboard-${var.stack_name}"
  }

  # Command override (if needed)
  command = [
    "python",
    "/app/app.py"
  ]

  # Working directory
  working_dir = "/app"
}

# Store dashboard configuration
resource "local_file" "dashboard_config" {
  count = var.enable_dashboard ? 1 : 0

  filename = "${path.module}/.dashboard_config.json"

  content = jsonencode({
    url = "http://localhost:${var.dashboard_port}"

    endpoints = {
      health       = "http://localhost:${var.dashboard_port}/health"
      metrics      = "http://localhost:${var.dashboard_port}/metrics"
      api_status   = "http://localhost:${var.dashboard_port}/api/status"
      api_stacks   = "http://localhost:${var.dashboard_port}/api/stacks"
      api_services = "http://localhost:${var.dashboard_port}/api/services"
      websocket    = "ws://localhost:${var.dashboard_port}/ws"
    }

    integrations = {
      gitea = {
        url      = local.gitea_root_url
        internal = "http://${docker_container.gitea.name}:${var.gitea_http_port}"
      }
      postgres = {
        host     = docker_container.postgres_gitea.name
        port     = 5432
        database = var.postgres_database
      }
      docker = {
        socket = "/var/run/docker.sock"
      }
    }

    monitoring = {
      metrics_enabled = true
      metrics_token   = local.gitea_metrics_token
    }
  })

  file_permission = "0644"
}