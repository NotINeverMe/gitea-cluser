# Gitea Git Server Container

# Pull Gitea image
resource "docker_image" "gitea" {
  name         = var.gitea_image
  keep_locally = true
}

# Gitea container
resource "docker_container" "gitea" {
  name  = var.stack_name
  image = docker_image.gitea.image_id

  restart = "unless-stopped"

  # Environment variables for Gitea configuration
  env = [
    # Database configuration
    "GITEA__database__DB_TYPE=postgres",
    "GITEA__database__HOST=${docker_container.postgres_gitea.name}:5432",
    "GITEA__database__NAME=${var.postgres_database}",
    "GITEA__database__USER=${var.postgres_user}",
    "GITEA__database__PASSWD=${local.postgres_password}",

    # Server configuration
    "GITEA__server__DOMAIN=${var.gitea_domain}",
    "GITEA__server__SSH_DOMAIN=${var.gitea_domain}",
    "GITEA__server__ROOT_URL=${local.gitea_root_url}",
    "GITEA__server__HTTP_PORT=${var.gitea_http_port}",
    "GITEA__server__SSH_PORT=${var.gitea_ssh_port}",
    "GITEA__server__START_SSH_SERVER=true",
    "GITEA__server__LFS_START_SERVER=true",
    "GITEA__server__OFFLINE_MODE=false",

    # Security configuration
    "GITEA__security__INSTALL_LOCK=true",
    "GITEA__security__SECRET_KEY=${local.gitea_secret_key}",
    "GITEA__security__INTERNAL_TOKEN=${local.gitea_internal_token}",
    "GITEA__security__PASSWORD_HASH_ALGO=argon2",
    "GITEA__security__MIN_PASSWORD_LENGTH=14",
    "GITEA__security__PASSWORD_COMPLEXITY=lower,upper,digit,spec",

    # Session configuration
    "GITEA__session__PROVIDER=db",
    "GITEA__session__COOKIE_SECURE=${var.gitea_cookie_secure}",
    "GITEA__session__COOKIE_NAME=gitea_session",

    # Logging configuration
    "GITEA__log__MODE=console,file",
    "GITEA__log__LEVEL=Info",
    "GITEA__log__ROOT_PATH=/var/lib/gitea/log",
    "GITEA__log__ENABLE_ACCESS_LOG=true",

    # Repository configuration
    "GITEA__repository__ROOT=/var/lib/gitea/git/repositories",
    "GITEA__repository__DEFAULT_BRANCH=main",
    "GITEA__repository__ENABLE_PUSH_CREATE_USER=true",
    "GITEA__repository__ENABLE_PUSH_CREATE_ORG=true",

    # Service configuration
    "GITEA__service__DISABLE_REGISTRATION=${var.gitea_disable_registration}",
    "GITEA__service__REQUIRE_SIGNIN_VIEW=${var.gitea_require_signin_view}",
    "GITEA__service__REGISTER_EMAIL_CONFIRM=false",
    "GITEA__service__ENABLE_NOTIFY_MAIL=false",
    "GITEA__service__DEFAULT_KEEP_EMAIL_PRIVATE=true",
    "GITEA__service__DEFAULT_ALLOW_CREATE_ORGANIZATION=true",

    # OAuth2 configuration
    "GITEA__oauth2__ENABLE=true",
    "GITEA__oauth2__JWT_SECRET=${local.gitea_oauth2_jwt_secret}",

    # Actions (CI/CD) configuration
    "GITEA__actions__ENABLED=true",
    "GITEA__actions__DEFAULT_ACTIONS_URL=https://github.com",

    # Webhook configuration
    "GITEA__webhook__ALLOWED_HOST_LIST=*",
    "GITEA__webhook__SKIP_TLS_VERIFY=${var.gitea_webhook_skip_tls}",

    # Metrics configuration (Prometheus)
    "GITEA__metrics__ENABLED=true",
    "GITEA__metrics__TOKEN=${local.gitea_metrics_token}",

    # Admin user (created on first run)
    "GITEA__admin__USERNAME=${var.admin_username}",
    "GITEA__admin__PASSWORD=${var.admin_password}",
    "GITEA__admin__EMAIL=${var.admin_email}",

    # User/UID for rootless
    "USER_UID=${var.gitea_user_uid}",
    "USER_GID=${var.gitea_user_gid}",
  ]

  # Port mappings
  ports {
    internal = var.gitea_http_port
    external = var.gitea_http_port
    ip       = "0.0.0.0"
  }

  ports {
    internal = var.gitea_ssh_port
    external = var.gitea_ssh_port
    ip       = "0.0.0.0"
  }

  # Volume mounts
  volumes {
    volume_name    = docker_volume.gitea_data.name
    container_path = "/var/lib/gitea"
  }

  volumes {
    volume_name    = docker_volume.gitea_config.name
    container_path = "/etc/gitea"
  }

  volumes {
    host_path      = "/etc/timezone"
    container_path = "/etc/timezone"
    read_only      = true
  }

  volumes {
    host_path      = "/etc/localtime"
    container_path = "/etc/localtime"
    read_only      = true
  }

  # Network attachments
  networks_advanced {
    name = docker_network.gitea_default.name
  }

  networks_advanced {
    name = docker_network.gitea_data.name
  }

  networks_advanced {
    name = docker_network.gitea_monitoring.name
  }

  # Health check
  healthcheck {
    test = ["CMD-SHELL", "curl -f http://localhost:${var.gitea_http_port}/api/healthz || exit 1"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
    start_period = "60s"
  }

  # Resource limits
  cpu_limit    = var.gitea_cpu_limit * 1000  # Convert to millicores
  memory       = var.gitea_memory_limit      # In MB
  memory_swap  = var.gitea_memory_limit      # Same as memory to disable swap

  # Labels
  dynamic "labels" {
    for_each = local.stack_labels.gitea
    content {
      label = labels.key
      value = labels.value
    }
  }

  # Additional Traefik labels if needed
  labels {
    label = "traefik.enable"
    value = "true"
  }

  labels {
    label = "traefik.http.routers.gitea.rule"
    value = "Host(`${var.gitea_domain}`)"
  }

  labels {
    label = "traefik.http.services.gitea.loadbalancer.server.port"
    value = tostring(var.gitea_http_port)
  }

  # Dependencies
  depends_on = [
    docker_container.postgres_gitea,
    docker_network.gitea_default,
    docker_network.gitea_data,
    docker_network.gitea_monitoring,
    docker_volume.gitea_data,
    docker_volume.gitea_config
  ]

  # Ensure proper cleanup
  must_run = true

  lifecycle {
    ignore_changes = [
      env,  # Ignore environment changes to prevent recreation
    ]
  }

  # Log configuration
  log_driver = "json-file"
  log_opts = {
    "max-size" = "50m"
    "max-file" = "5"
  }
}

# Store Gitea admin credentials securely
resource "local_sensitive_file" "gitea_admin_credentials" {
  filename = "${path.module}/.gitea_admin.json"

  content = jsonencode({
    url      = local.gitea_root_url
    username = var.admin_username
    password = var.admin_password
    email    = var.admin_email

    api_endpoints = {
      health  = "${local.gitea_root_url}api/healthz"
      swagger = "${local.gitea_root_url}api/swagger"
      v1      = "${local.gitea_root_url}api/v1"
    }

    metrics = {
      enabled  = true
      endpoint = "${local.gitea_root_url}metrics"
      token    = local.gitea_metrics_token
    }
  })

  file_permission = "0600"
}