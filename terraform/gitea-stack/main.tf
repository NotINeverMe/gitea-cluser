# Main Terraform configuration for Gitea Docker Stack

# Local values for computed configurations
locals {
  # Use provided values or generate random ones
  postgres_password        = var.postgres_password != null ? var.postgres_password : random_password.postgres_password[0].result
  gitea_secret_key        = var.gitea_secret_key != null ? var.gitea_secret_key : random_password.gitea_secret_key[0].result
  gitea_internal_token    = var.gitea_internal_token != null ? var.gitea_internal_token : random_password.gitea_internal_token[0].result
  gitea_oauth2_jwt_secret = var.gitea_oauth2_jwt_secret != null ? var.gitea_oauth2_jwt_secret : random_password.gitea_oauth2_jwt_secret[0].result
  gitea_metrics_token     = var.gitea_metrics_token != null ? var.gitea_metrics_token : random_password.gitea_metrics_token[0].result

  # Compute root URL if not provided
  gitea_root_url = var.gitea_root_url != "" ? var.gitea_root_url : "http://${var.gitea_domain}:${var.gitea_http_port}/"

  # Common labels for all resources
  common_labels = merge(
    {
      "com.devsecops.stack"       = var.stack_name
      "com.devsecops.managed-by"  = "terraform"
      "com.devsecops.environment" = terraform.workspace
    },
    var.additional_labels
  )

  # Stack-specific labels
  stack_labels = {
    database = merge(local.common_labels, {
      "com.devsecops.category" = "database"
      "com.devsecops.tier"     = "supporting"
      "com.gitea.component"    = "database"
      "com.gitea.tier"         = "data"
      "com.cmmc.asset-category" = "SPA"
      "com.cmmc.control"       = "AC.L2-3.1.1,AU.L2-3.3.1"
    })

    gitea = merge(local.common_labels, {
      "com.devsecops.category" = "git"
      "com.devsecops.tier"     = "core"
      "com.gitea.component"    = "server"
      "com.gitea.tier"         = "application"
      "com.cmmc.asset-category" = "CUI"
      "com.cmmc.control"       = "AC.L2-3.1.1,AU.L2-3.3.1,IA.L2-3.5.1,SC.L2-3.13.8"
    })

    runner = merge(local.common_labels, {
      "com.devsecops.category" = "cicd"
      "com.devsecops.tier"     = "core"
      "com.gitea.component"    = "runner"
      "com.gitea.tier"         = "build"
      "com.cmmc.asset-category" = "SPC"
      "com.cmmc.control"       = "SI.L2-3.14.1,CM.L2-3.4.2"
    })

    caddy = merge(local.common_labels, {
      "com.devsecops.category" = "proxy"
      "com.devsecops.tier"     = "supporting"
      "com.gitea.component"    = "proxy"
      "com.gitea.tier"         = "edge"
      "com.cmmc.asset-category" = "SPA"
      "com.cmmc.control"       = "SC.L2-3.13.8,SC.L2-3.13.11"
    })

    dashboard = merge(local.common_labels, {
      "com.devsecops.category" = "management"
      "com.devsecops.tier"     = "supporting"
      "com.gitea.component"    = "dashboard"
      "com.gitea.tier"         = "management"
    })
  }

  # Network names
  network_names = {
    default    = "${var.stack_name}_default"
    data       = "${var.stack_name}_data"
    monitoring = "${var.stack_name}_monitoring"
  }

  # Volume names
  volume_names = {
    gitea_data    = "${var.stack_name}_data"
    gitea_config  = "${var.stack_name}_config"
    postgres_data = "postgres_${var.stack_name}_data"
    actions_cache = "${var.stack_name}_actions_cache"
    caddy_data    = "caddy_${var.stack_name}_data"
    caddy_config  = "caddy_${var.stack_name}_config"
  }
}

# Evidence logging for compliance
resource "local_file" "deployment_evidence" {
  filename = "${path.module}/deployment_evidence_${formatdate("YYYY-MM-DD_HHmmss", timestamp())}.json"

  content = jsonencode({
    deployment_timestamp = timestamp()
    terraform_version    = terraform.version
    workspace           = terraform.workspace
    stack_name          = var.stack_name

    components_deployed = {
      gitea     = true
      postgres  = true
      runner    = var.enable_runner
      caddy     = var.enable_caddy
      dashboard = var.enable_dashboard
    }

    security_configuration = {
      rootless_deployment      = var.gitea_rootless
      registration_disabled    = var.gitea_disable_registration
      password_complexity      = "lower,upper,digit,spec"
      min_password_length      = 14
      password_hash_algo       = "argon2"
      secure_cookies          = var.gitea_cookie_secure
      metrics_enabled         = true
      oauth2_enabled          = true
    }

    network_configuration = {
      isolated_data_network = true
      networks_created = [
        local.network_names.default,
        local.network_names.data,
        local.network_names.monitoring
      ]
    }

    resource_limits = {
      postgres = {
        cpu_limit    = var.postgres_cpu_limit
        memory_limit = var.postgres_memory_limit
      }
      gitea = {
        cpu_limit    = var.gitea_cpu_limit
        memory_limit = var.gitea_memory_limit
      }
      runner = {
        cpu_limit    = var.runner_cpu_limit
        memory_limit = var.runner_memory_limit
      }
    }

    ports_exposed = {
      gitea_http = var.gitea_http_port
      gitea_ssh  = var.gitea_ssh_port
      postgres   = var.postgres_port
      caddy_https = var.enable_caddy ? var.caddy_https_port : null
      caddy_http  = var.enable_caddy ? var.caddy_http_port : null
      dashboard   = var.enable_dashboard ? var.dashboard_port : null
    }

    compliance_controls = {
      cmmc_controls = [
        "AC.L2-3.1.1",
        "AU.L2-3.3.1",
        "IA.L2-3.5.1",
        "SC.L2-3.13.8",
        "SC.L2-3.13.11",
        "SI.L2-3.14.1",
        "CM.L2-3.4.2"
      ]
    }
  })

  lifecycle {
    create_before_destroy = false
  }
}