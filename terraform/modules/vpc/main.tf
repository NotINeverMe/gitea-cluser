# VPC Module - Main Configuration
# CMMC 2.0: CM.L2-3.4.9 (Least Functionality - Network Segmentation)
# NIST SP 800-171: 3.4.9 (Configure for Essential Capabilities)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# VPC NETWORK
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                            = var.network_name
  project                        = var.project_id
  auto_create_subnetworks        = var.auto_create_subnetworks
  routing_mode                   = var.routing_mode
  mtu                           = var.mtu
  delete_default_routes_on_create = true
  description                    = "VPC network for ${var.network_name}"

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# SUBNETS
# -----------------------------------------------------------------------------

resource "google_compute_subnetwork" "subnets" {
  for_each = { for subnet in var.subnets : subnet.subnet_name => subnet }

  name                     = each.value.subnet_name
  project                  = var.project_id
  network                  = google_compute_network.vpc.id
  region                   = each.value.subnet_region
  ip_cidr_range           = each.value.subnet_ip
  description             = lookup(each.value, "description", "Managed by Terraform")
  private_ip_google_access = var.enable_private_google_access
  private_ipv6_google_access = var.enable_private_ipv6_google_access

  # Secondary ranges for GKE
  dynamic "secondary_ip_range" {
    for_each = lookup(var.secondary_ranges, each.value.subnet_name, [])
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }

  # Flow logs configuration
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = lookup(var.flow_logs_config, "aggregation_interval", "INTERVAL_10_MIN")
      flow_sampling       = lookup(var.flow_logs_config, "flow_sampling", 0.5)
      metadata           = lookup(var.flow_logs_config, "metadata", "INCLUDE_ALL_METADATA")
      metadata_fields    = lookup(var.flow_logs_config, "metadata_fields", [])
      filter_expr        = lookup(var.flow_logs_config, "filter_expr", "")
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# CLOUD ROUTER
# -----------------------------------------------------------------------------

resource "google_compute_router" "router" {
  count = var.enable_cloud_nat ? 1 : 0

  name    = "${var.network_name}-router"
  project = var.project_id
  network = google_compute_network.vpc.id
  region  = var.region

  bgp {
    asn               = 64514
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]

    # Advertise custom IP ranges if provided
    dynamic "advertised_ip_ranges" {
      for_each = var.advertised_ip_ranges
      content {
        range = advertised_ip_ranges.value
      }
    }
  }
}

# -----------------------------------------------------------------------------
# CLOUD NAT
# -----------------------------------------------------------------------------

resource "google_compute_router_nat" "nat" {
  count = var.enable_cloud_nat ? 1 : 0

  name                               = var.nat_name
  project                           = var.project_id
  router                            = google_compute_router.router[0].name
  region                            = var.region
  nat_ip_allocate_option            = var.nat_ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Manual IP allocation for production
  nat_ips = var.nat_ip_allocate_option == "MANUAL_ONLY" ? google_compute_address.nat_ips[*].self_link : []

  # Logging configuration
  log_config {
    enable = var.nat_log_enabled
    filter = var.nat_log_enabled ? "ALL" : "ERRORS_ONLY"
  }

  # Minimum ports per VM
  min_ports_per_vm = 64

  # Timeouts
  udp_idle_timeout_sec             = 30
  icmp_idle_timeout_sec           = 30
  tcp_established_idle_timeout_sec = 1200
  tcp_transitory_idle_timeout_sec = 30
}

# -----------------------------------------------------------------------------
# NAT IP ADDRESSES (for production)
# -----------------------------------------------------------------------------

resource "google_compute_address" "nat_ips" {
  count = var.nat_ip_allocate_option == "MANUAL_ONLY" ? var.nat_ip_count : 0

  name         = "${var.nat_name}-ip-${count.index}"
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# FIREWALL RULES
# -----------------------------------------------------------------------------

resource "google_compute_firewall" "rules" {
  for_each = var.firewall_rules

  name        = "${var.network_name}-${each.key}"
  project     = var.project_id
  network     = google_compute_network.vpc.name
  description = each.value.description
  direction   = each.value.direction
  priority    = each.value.priority
  disabled    = lookup(each.value, "disabled", false)

  # Source/destination ranges
  source_ranges      = each.value.direction == "INGRESS" ? lookup(each.value, "ranges", null) : null
  destination_ranges = each.value.direction == "EGRESS" ? lookup(each.value, "ranges", null) : null

  # Source/target tags
  source_tags = lookup(each.value, "source_tags", null)
  target_tags = lookup(each.value, "target_tags", null)

  # Service accounts
  source_service_accounts = lookup(each.value, "source_service_accounts", null)
  target_service_accounts = lookup(each.value, "target_service_accounts", null)

  # Allow rules
  dynamic "allow" {
    for_each = lookup(each.value, "allow", [])
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }

  # Deny rules
  dynamic "deny" {
    for_each = lookup(each.value, "deny", [])
    content {
      protocol = deny.value.protocol
      ports    = deny.value.ports
    }
  }

  # Log configuration
  dynamic "log_config" {
    for_each = lookup(each.value, "enable_logging", false) ? [1] : []
    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}

# -----------------------------------------------------------------------------
# CUSTOM FIREWALL RULES (environment-specific)
# -----------------------------------------------------------------------------

resource "google_compute_firewall" "custom_rules" {
  for_each = var.custom_firewall_rules

  name        = "${var.network_name}-custom-${each.key}"
  project     = var.project_id
  network     = google_compute_network.vpc.name
  description = each.value.description
  direction   = each.value.direction
  priority    = each.value.priority

  source_ranges = lookup(each.value, "ranges", [])

  allow {
    protocol = each.value.protocol
    ports    = each.value.ports
  }

  target_tags = lookup(each.value, "target_tags", [])
}

# -----------------------------------------------------------------------------
# PRIVATE SERVICE CONNECTION
# -----------------------------------------------------------------------------

resource "google_compute_global_address" "private_service_connection" {
  count = var.enable_private_service_connection ? 1 : 0

  name          = "${var.network_name}-private-service-connection"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_networking_connection" "private_service_connection" {
  count = var.enable_private_service_connection ? 1 : 0

  network                 = google_compute_network.vpc.id
  service                = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_connection[0].name]
}

# -----------------------------------------------------------------------------
# DNS MANAGED ZONE
# -----------------------------------------------------------------------------

resource "google_dns_managed_zone" "private_zone" {
  count = var.enable_dns_managed_zone ? 1 : 0

  name        = var.dns_zone_name
  project     = var.project_id
  dns_name    = var.dns_zone_dns_name
  description = "Private DNS zone for ${var.network_name}"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }

  dnssec_config {
    kind          = "dns#managedZoneDnsSecConfig"
    non_existence = "nsec3"
    state         = "on"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# VPC SERVICE CONTROLS (Production only)
# -----------------------------------------------------------------------------

resource "google_access_context_manager_service_perimeter" "vpc_sc" {
  count = var.enable_vpc_service_controls ? 1 : 0

  parent = "accessPolicies/${var.access_context_policy}"
  name   = "accessPolicies/${var.access_context_policy}/servicePerimeters/${var.vpc_sc_perimeter_name}"
  title  = "${var.network_name} Service Perimeter"

  status {
    resources = var.vpc_sc_resources

    restricted_services = [
      "storage.googleapis.com",
      "compute.googleapis.com",
      "container.googleapis.com",
      "sql.googleapis.com",
      "bigquery.googleapis.com",
      "bigtable.googleapis.com",
      "cloudkms.googleapis.com",
      "pubsub.googleapis.com",
    ]

    # VPC accessible services
    vpc_accessible_services {
      enable_restriction = true
      allowed_services  = var.vpc_sc_allowed_services
    }
  }

  # Ingress policies
  dynamic "status" {
    for_each = var.vpc_sc_ingress_policies
    content {
      ingress_from {
        identities = status.value.identities
        sources {
          resource = status.value.resource
        }
      }
      ingress_to {
        operations {
          service_name = status.value.service
          method_selectors {
            method = status.value.method
          }
        }
      }
    }
  }

  # Egress policies
  dynamic "status" {
    for_each = var.vpc_sc_egress_policies
    content {
      egress_from {
        identities = status.value.identities
      }
      egress_to {
        resources = status.value.resources
        operations {
          service_name = status.value.service
          method_selectors {
            method = status.value.method
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# NETWORK PEERING (if needed)
# -----------------------------------------------------------------------------

resource "google_compute_network_peering" "peering" {
  for_each = var.network_peerings

  name                 = each.key
  network             = google_compute_network.vpc.id
  peer_network        = each.value.peer_network
  export_custom_routes = lookup(each.value, "export_custom_routes", false)
  import_custom_routes = lookup(each.value, "import_custom_routes", false)
}

# -----------------------------------------------------------------------------
# DEFAULT ROUTE TO INTERNET GATEWAY
# -----------------------------------------------------------------------------

resource "google_compute_route" "default_internet" {
  name             = "${var.network_name}-default-internet"
  project         = var.project_id
  network         = google_compute_network.vpc.name
  dest_range      = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority        = 1000
}