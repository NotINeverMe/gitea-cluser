# Network Infrastructure for Gitea GCP Deployment
# CMMC 2.0 Level 2 Compliant Network Configuration
# NIST SP 800-171 Rev. 2 Controls Implementation

# ============================================================================
# VPC NETWORK - SC.L2-3.13.1: Boundary Protection
# ============================================================================

resource "google_compute_network" "gitea_network" {
  name                            = local.network_name
  auto_create_subnetworks        = false
  routing_mode                   = "REGIONAL"
  delete_default_routes_on_create = true

  description = "VPC network for Gitea deployment - CMMC Level 2 compliant"
}

# Custom subnet with private Google access
# SC.L2-3.13.2: Shared System Resources
resource "google_compute_subnetwork" "gitea_subnet" {
  name          = local.subnet_name
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.gitea_network.id
  region        = var.region

  # Enable private Google access for secure API communication
  private_ip_google_access = true

  # Enable VPC Flow Logs - AU.L2-3.3.1: Event Logging
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling       = 1.0
    metadata           = "INCLUDE_ALL_METADATA"
    metadata_fields    = []
  }

  description = "Subnet for Gitea instances with VPC Flow Logs enabled"
}

# ============================================================================
# CLOUD ROUTER & NAT - SC.L2-3.13.5: Publicly Accessible Systems
# ============================================================================

resource "google_compute_router" "gitea_router" {
  name    = "${local.name_prefix}-router"
  network = google_compute_network.gitea_network.id
  region  = var.region

  bgp {
    asn                = 64514
    advertise_mode     = "CUSTOM"
    advertised_groups  = ["ALL_SUBNETS"]
    keepalive_interval = 20
  }

  description = "Router for Cloud NAT - provides outbound internet access"
}

# Cloud NAT for secure outbound internet access
# SC.L2-3.13.5: Control connections to external systems
resource "google_compute_router_nat" "gitea_nat" {
  count = var.enable_cloud_nat ? 1 : 0

  name                               = "${local.name_prefix}-nat"
  router                            = google_compute_router.gitea_router.name
  region                            = google_compute_router.gitea_router.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gitea_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # Configure NAT timeouts for security
  udp_idle_timeout_sec             = 30
  icmp_idle_timeout_sec            = 30
  tcp_established_idle_timeout_sec = 1200
  tcp_transitory_idle_timeout_sec  = 30
  tcp_time_wait_timeout_sec        = 120

  # Enable logging for audit trail - AU.L2-3.3.1
  log_config {
    enable = true
    filter = "ALL"
  }
}

# ============================================================================
# FIREWALL RULES - AC.L2-3.1.3: Flow Control
# ============================================================================

# Default deny all ingress rule
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${local.name_prefix}-deny-all-ingress"
  network  = google_compute_network.gitea_network.name
  priority = 65534

  direction = "INGRESS"

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  description = "Default deny all ingress traffic - AC.L2-3.1.3"

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow HTTPS traffic (port 443) - SC.L2-3.13.8: Transmission Confidentiality
resource "google_compute_firewall" "allow_https" {
  name    = "${local.name_prefix}-allow-https"
  network = google_compute_network.gitea_network.name
  priority = 1000

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = var.allowed_https_cidr_ranges
  target_tags   = ["gitea-server"]

  description = "Allow HTTPS traffic for Gitea web interface - SC.L2-3.13.8"

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow SSH via IAP - IA.L2-3.5.1: Identification and Authentication
resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap ? 1 : 0

  name    = "${local.name_prefix}-allow-iap-ssh"
  network = google_compute_network.gitea_network.name
  priority = 1001

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP proxy IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["gitea-server"]

  description = "Allow SSH from IAP for secure administration - IA.L2-3.5.1"

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow Git SSH (custom port 10001) - AC.L2-3.1.2: Authorized Access Control
resource "google_compute_firewall" "allow_git_ssh" {
  count = length(var.allowed_git_ssh_cidr_ranges) > 0 ? 1 : 0

  name    = "${local.name_prefix}-allow-git-ssh"
  network = google_compute_network.gitea_network.name
  priority = 1002

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["10001"]
  }

  source_ranges = var.allowed_git_ssh_cidr_ranges
  target_tags   = ["gitea-server"]

  description = "Allow Git SSH access on custom port - AC.L2-3.1.2"

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow health checks from Google Load Balancers
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${local.name_prefix}-allow-health-checks"
  network = google_compute_network.gitea_network.name
  priority = 1003

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  # Google health check IP ranges
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["gitea-server"]

  description = "Allow health checks from Google Cloud"

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Egress rule for updates and package installation
resource "google_compute_firewall" "allow_egress" {
  name     = "${local.name_prefix}-allow-egress"
  network  = google_compute_network.gitea_network.name
  priority = 1000

  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "22", "25", "587", "465"]
  }

  allow {
    protocol = "udp"
    ports    = ["53", "123"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags       = ["gitea-server"]

  description = "Allow controlled egress for updates and email"

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ============================================================================
# CLOUD ARMOR WAF - SC.L2-3.13.1: Boundary Protection
# ============================================================================

# Cloud Armor security policy
resource "google_compute_security_policy" "gitea_waf" {
  count = var.enable_cloud_armor ? 1 : 0

  name        = "${local.name_prefix}-waf-policy"
  description = "Cloud Armor WAF policy for Gitea - SC.L2-3.13.1"

  # Default rule - allow traffic
  rule {
    action   = "allow"
    priority = "2147483647"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    description = "Default rule"
  }

  # Block common attack patterns - OWASP Top 10
  rule {
    action   = "deny(403)"
    priority = "1000"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }

    description = "Block XSS attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "1001"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }

    description = "Block SQL injection attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "1002"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-v33-stable')"
      }
    }

    description = "Block local file inclusion attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "1003"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-v33-stable')"
      }
    }

    description = "Block remote file inclusion attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "1004"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-v33-stable')"
      }
    }

    description = "Block remote code execution attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "1005"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('methodenforcement-v33-stable')"
      }
    }

    description = "Block invalid HTTP methods"
  }

  # Rate limiting rule - SI.L2-3.14.6: Information System Monitoring
  rule {
    action   = "rate_based_ban"
    priority = "2000"

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }

      ban_duration_sec = 600
    }

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    description = "Rate limiting - 100 requests per minute per IP"
  }

  # DDoS protection - adaptive protection
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }
}

# ============================================================================
# STATIC IP ADDRESS
# ============================================================================

resource "google_compute_address" "gitea_ip" {
  name         = "${local.name_prefix}-gitea-ip"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  region       = var.region

  description = "Static external IP for Gitea instance"
}

# ============================================================================
# VPC ROUTES
# ============================================================================

# Default route to internet gateway
resource "google_compute_route" "default_internet" {
  name             = "${local.name_prefix}-default-internet"
  network          = google_compute_network.gitea_network.name
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000

  description = "Default route to internet"
}

# Route for private Google access
resource "google_compute_route" "private_google_access" {
  name             = "${local.name_prefix}-private-google-access"
  network          = google_compute_network.gitea_network.name
  dest_range       = "199.36.153.8/30"
  next_hop_gateway = "default-internet-gateway"
  priority         = 900

  description = "Route for private Google API access"
}