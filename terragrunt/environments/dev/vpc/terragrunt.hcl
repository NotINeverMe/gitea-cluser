# Development VPC Configuration
# CMMC 2.0: CM.L2-3.4.9 (Least Functionality)

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "vpc_common" {
  path = "${get_terragrunt_dir()}/../../../_envcommon/vpc.hcl"
}

# Development-specific VPC configuration
inputs = {
  # Override any common settings for dev
  enable_flow_logs = false  # Save costs in dev
  flow_logs_sampling = 0.1  # Sample 10% of flows

  # Dev-specific firewall rules
  custom_firewall_rules = {
    allow-dev-ssh = {
      description = "Allow SSH for development"
      direction   = "INGRESS"
      priority    = 1000
      ranges      = ["10.0.0.0/8"]
      ports       = ["22"]
      protocol    = "tcp"
    }
  }

  # Development NAT configuration
  nat_ip_allocate_option = "AUTO_ONLY"
  nat_log_enabled       = false
}