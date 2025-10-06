# Development Environment Configuration
# CMMC 2.0: CM.L2-3.4.2 (Baseline Configuration)

locals {
  # Environment settings
  environment = "dev"

  # GCP Project Configuration
  project_id = "gitea-dev-project"
  region     = "us-central1"
  zone       = "us-central1-a"

  # Network Configuration
  vpc_cidr = "10.10.0.0/16"
  subnet_ranges = {
    compute     = "10.10.1.0/24"
    data        = "10.10.2.0/24"
    management  = "10.10.3.0/24"
    gke_nodes   = "10.10.10.0/24"
    gke_pods    = "10.10.20.0/20"
    gke_services = "10.10.40.0/24"
  }

  # Security Settings
  allowed_ips = [
    "10.0.0.0/8",     # Internal networks only for dev
  ]

  # Resource Sizing (smaller for dev)
  compute_machine_type = "e2-medium"
  db_tier             = "db-f1-micro"
  gke_node_pool_size  = 1

  # Cost Controls
  auto_shutdown_enabled = true
  auto_shutdown_schedule = "0 20 * * *"  # 8 PM daily

  # Compliance Settings (relaxed for dev)
  require_approvals = false
  min_approvers    = 1
  allow_public_ip  = true
  require_ssl      = false

  # Monitoring (basic for dev)
  alert_email = "devops-dev@gitea.local"
  log_level   = "DEBUG"

  # Backup Settings (minimal for dev)
  backup_enabled = true
  backup_schedule = "0 2 * * 0"  # Weekly on Sunday
  retention_days = 7
}