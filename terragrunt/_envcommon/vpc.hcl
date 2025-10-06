# Common VPC Configuration for All Environments
# CMMC 2.0: CM.L2-3.4.2 (Baseline Configuration)

terraform {
  source = "${get_parent_terragrunt_dir()}/terraform/modules/vpc"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment
  project_id  = local.env_vars.locals.project_id
  region      = local.env_vars.locals.region
}

inputs = {
  # Network naming
  network_name = "${local.project_id}-${local.environment}-vpc"
  project_id   = local.project_id
  region       = local.region

  # Subnets configuration
  subnets = [
    {
      subnet_name   = "${local.project_id}-${local.environment}-compute"
      subnet_ip     = local.env_vars.locals.subnet_ranges.compute
      subnet_region = local.region
      description   = "Subnet for compute resources"
    },
    {
      subnet_name   = "${local.project_id}-${local.environment}-data"
      subnet_ip     = local.env_vars.locals.subnet_ranges.data
      subnet_region = local.region
      description   = "Subnet for data layer resources"
    },
    {
      subnet_name   = "${local.project_id}-${local.environment}-management"
      subnet_ip     = local.env_vars.locals.subnet_ranges.management
      subnet_region = local.region
      description   = "Subnet for management resources"
    },
  ]

  # Secondary ranges for GKE
  secondary_ranges = {
    "${local.project_id}-${local.environment}-compute" = [
      {
        range_name    = "gke-pods"
        ip_cidr_range = local.env_vars.locals.subnet_ranges.gke_pods
      },
      {
        range_name    = "gke-services"
        ip_cidr_range = local.env_vars.locals.subnet_ranges.gke_services
      }
    ]
  }

  # VPC native settings
  enable_vpc_native     = true
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  mtu                   = 1460

  # Private Google Access
  enable_private_google_access = true
  enable_private_ipv6_google_access = false

  # Flow logs configuration
  enable_flow_logs = true
  flow_logs_config = {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling       = local.environment == "prod" ? 0.5 : 0.1
    metadata           = "INCLUDE_ALL_METADATA"
    filter_expr        = ""
  }

  # Cloud NAT configuration
  enable_cloud_nat = true
  nat_name         = "${local.project_id}-${local.environment}-nat"
  nat_ip_allocate_option = local.environment == "prod" ? "MANUAL_ONLY" : "AUTO_ONLY"
  nat_log_enabled  = local.environment == "prod" ? true : false

  # Firewall rules
  firewall_rules = {
    # Deny all ingress by default (implicit)
    deny-all-ingress = {
      description = "Deny all ingress traffic"
      direction   = "INGRESS"
      priority    = 65534
      ranges      = ["0.0.0.0/0"]
      deny = [{
        protocol = "all"
        ports    = []
      }]
    }

    # Allow internal communication
    allow-internal = {
      description = "Allow internal VPC communication"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = [local.env_vars.locals.vpc_cidr]
      allow = [{
        protocol = "all"
        ports    = []
      }]
    }

    # Allow health checks
    allow-health-checks = {
      description = "Allow GCP health checks"
      direction   = "INGRESS"
      priority    = 1100
      ranges      = ["35.191.0.0/16", "130.211.0.0/22"]
      allow = [{
        protocol = "tcp"
        ports    = []
      }]
    }

    # Allow IAP for SSH (production only)
    allow-iap-ssh = {
      description = "Allow IAP SSH access"
      direction   = "INGRESS"
      priority    = 1200
      ranges      = ["35.235.240.0/20"]
      allow = [{
        protocol = "tcp"
        ports    = ["22"]
      }]
      target_tags = ["allow-iap-ssh"]
      disabled    = local.environment == "dev" ? true : false
    }
  }

  # VPC Service Controls (production only)
  enable_vpc_service_controls = local.environment == "prod" ? true : false
  vpc_sc_perimeter_name      = local.environment == "prod" ? local.env_vars.locals.vpc_sc_perimeter : null

  # DNS configuration
  enable_dns_managed_zone = true
  dns_zone_name          = "${local.environment}-gitea-local"
  dns_zone_dns_name      = "${local.environment}.gitea.local."

  # Shared VPC configuration (if needed)
  shared_vpc_host = false

  # Labels
  labels = {
    environment = local.environment
    managed_by  = "terragrunt"
    module      = "vpc"
    cmmc        = "CM.L2-3.4.9"
    nist        = "SP-800-171-3.4.9"
  }
}