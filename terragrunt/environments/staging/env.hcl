# Staging Environment Configuration
# CMMC 2.0: CM.L2-3.4.2 (Baseline Configuration)

locals {
  # Environment settings
  environment = "staging"

  # GCP Project Configuration
  project_id = "gitea-staging-project"
  region     = "us-central1"
  zone       = "us-central1-b"

  # Network Configuration
  vpc_cidr = "10.20.0.0/16"
  subnet_ranges = {
    compute     = "10.20.1.0/24"
    data        = "10.20.2.0/24"
    management  = "10.20.3.0/24"
    gke_nodes   = "10.20.10.0/24"
    gke_pods    = "10.20.20.0/20"
    gke_services = "10.20.40.0/24"
  }

  # Security Settings
  allowed_ips = [
    "10.0.0.0/8",     # Internal networks
    "35.235.240.0/20", # GCP IAP ranges for testing
  ]

  # Resource Sizing (production-like)
  compute_machine_type = "n2-standard-2"
  db_tier             = "db-n1-standard-1"
  gke_node_pool_size  = 2

  # Cost Controls
  auto_shutdown_enabled = false
  preemptible_nodes    = true

  # Compliance Settings (stricter than dev)
  require_approvals = true
  min_approvers    = 1
  allow_public_ip  = false
  require_ssl      = true

  # Monitoring (enhanced for staging)
  alert_email = "devops-staging@gitea.local"
  log_level   = "INFO"

  # Backup Settings (daily for staging)
  backup_enabled = true
  backup_schedule = "0 2 * * *"  # Daily at 2 AM
  retention_days = 14
}