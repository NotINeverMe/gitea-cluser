# Docker Networks for Gitea Stack

# Default network for general communication
resource "docker_network" "gitea_default" {
  name   = local.network_names.default
  driver = "bridge"

  ipam_config {
    subnet  = var.network_subnet_default
    gateway = cidrhost(var.network_subnet_default, 1)
  }

  options = {
    "com.docker.network.bridge.name" = "br-${var.stack_name}-default"
  }

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.network.type"
    value = "default"
  }

  labels {
    label = "com.devsecops.managed-by"
    value = "terraform"
  }

  labels {
    label = "com.devsecops.environment"
    value = terraform.workspace
  }
}

# Internal network for database communication (no external access)
resource "docker_network" "gitea_data" {
  name     = local.network_names.data
  driver   = "bridge"
  internal = true  # No external internet access

  ipam_config {
    subnet  = var.network_subnet_data
    gateway = cidrhost(var.network_subnet_data, 1)
  }

  options = {
    "com.docker.network.bridge.name" = "br-${var.stack_name}-data"
  }

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.network.type"
    value = "data"
  }

  labels {
    label = "com.devsecops.network.internal"
    value = "true"
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
    label = "com.cmmc.control"
    value = "SC.L2-3.13.8"
  }
}

# Monitoring network for metrics and observability
resource "docker_network" "gitea_monitoring" {
  name   = local.network_names.monitoring
  driver = "bridge"

  ipam_config {
    subnet  = var.network_subnet_monitoring
    gateway = cidrhost(var.network_subnet_monitoring, 1)
  }

  options = {
    "com.docker.network.bridge.name" = "br-${var.stack_name}-monitoring"
  }

  labels {
    label = "com.devsecops.stack"
    value = var.stack_name
  }

  labels {
    label = "com.devsecops.network.type"
    value = "monitoring"
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
    label = "com.cmmc.control"
    value = "AU.L2-3.3.1"
  }
}