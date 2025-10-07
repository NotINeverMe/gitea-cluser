# Gitea Actions Runner Container

# Pull runner image (conditional)
resource "docker_image" "runner" {
  count        = var.enable_runner ? 1 : 0
  name         = var.runner_image
  keep_locally = true
}

# Gitea Actions runner container (conditional)
resource "docker_container" "gitea_runner" {
  count = var.enable_runner ? 1 : 0
  name  = "${var.stack_name}-runner"
  image = docker_image.runner[0].image_id

  restart = "unless-stopped"

  # Privileged mode required for Docker-in-Docker
  privileged = true

  # Environment variables
  env = [
    "GITEA_INSTANCE_URL=http://${docker_container.gitea.name}:${var.gitea_http_port}",
    "GITEA_RUNNER_REGISTRATION_TOKEN=${var.gitea_runner_token}",
    "GITEA_RUNNER_NAME=docker-runner-1",
    "GITEA_RUNNER_LABELS=ubuntu-latest,ubuntu-22.04,ubuntu-20.04,docker"
  ]

  # Volume mounts
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  volumes {
    volume_name    = docker_volume.actions_cache.name
    container_path = "/data"
  }

  dynamic "volumes" {
    for_each = var.runner_config_path != "" ? [1] : []
    content {
      host_path      = var.runner_config_path
      container_path = "/config.yaml"
      read_only      = true
    }
  }

  # Network attachments
  networks_advanced {
    name = docker_network.gitea_default.name
  }

  # Resource limits
  cpu_limit    = var.runner_cpu_limit * 1000  # Convert to millicores
  memory       = var.runner_memory_limit      # In MB
  memory_swap  = var.runner_memory_limit      # Same as memory to disable swap

  # Labels
  dynamic "labels" {
    for_each = local.stack_labels.runner
    content {
      label = labels.key
      value = labels.value
    }
  }

  # Dependencies
  depends_on = [
    docker_container.gitea,
    docker_network.gitea_default,
    docker_volume.actions_cache
  ]

  # Ensure proper cleanup
  must_run = true

  # Log configuration
  log_driver = "json-file"
  log_opts = {
    "max-size" = "100m"
    "max-file" = "5"
  }
}

# Create runner configuration file if not provided
resource "local_file" "runner_config" {
  count = var.enable_runner && var.runner_config_path == "" ? 1 : 0

  filename = "${path.module}/runner-config.yaml"

  content = yamlencode({
    log = {
      level = "info"
    }

    runner = {
      file = ".runner"
      capacity = 2
      envs = {}
      env_file = ""
      timeout = "3h"
      insecure = false
      fetch_timeout = "5s"
      fetch_interval = "2s"
      labels = [
        "ubuntu-latest:docker://node:16-bullseye",
        "ubuntu-22.04:docker://node:16-bullseye",
        "ubuntu-20.04:docker://node:16-bullseye"
      ]
    }

    cache = {
      enabled = true
      dir = "/data/cache"
      host = ""
      port = 0
    }

    container = {
      network = docker_network.gitea_default.name
      enable_ipv6 = false
      privileged = false
      options = ""
      workdir_parent = "/data/workdir"
      valid_volumes = []
      docker_host = ""
      force_pull = false
    }

    host = {
      workdir_parent = ""
    }
  })

  file_permission = "0644"
}