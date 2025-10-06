# Production Environment Configuration
# CMMC 2.0: CM.L2-3.4.2 (Baseline Configuration)
# NIST SP 800-171: 3.4.2 (Security Configuration)

locals {
  # Environment settings
  environment = "prod"

  # GCP Project Configuration
  project_id = "gitea-prod-project"
  region     = "us-central1"
  zone       = "us-central1-c"

  # Multi-zone for HA
  zones = ["us-central1-a", "us-central1-b", "us-central1-c"]

  # Network Configuration
  vpc_cidr = "10.30.0.0/16"
  subnet_ranges = {
    compute     = "10.30.1.0/24"
    data        = "10.30.2.0/24"
    management  = "10.30.3.0/24"
    gke_nodes   = "10.30.10.0/23"
    gke_pods    = "10.30.20.0/20"
    gke_services = "10.30.40.0/23"
  }

  # Security Settings (strictest)
  allowed_ips = [
    "10.30.0.0/16",    # Internal VPC only
  ]

  # VPC Service Controls for CUI data
  vpc_sc_perimeter = "gitea_prod_perimeter"

  # Resource Sizing (production scale)
  compute_machine_type = "n2-standard-4"
  db_tier             = "db-n1-standard-2"
  gke_node_pool_size  = 3
  gke_max_nodes      = 10

  # High Availability
  enable_regional_cluster = true
  enable_database_ha     = true
  enable_multi_zone     = true

  # Cost Controls
  auto_shutdown_enabled = false
  preemptible_nodes    = false
  committed_use_discount = true

  # Compliance Settings (strictest)
  require_approvals = true
  min_approvers    = 2
  allow_public_ip  = false
  require_ssl      = true
  require_cmek     = true
  require_vpc_sc   = true

  # Binary Authorization for GKE
  binary_authorization_enabled = true
  attestor_names = ["prod-attestor"]

  # Monitoring (comprehensive)
  alert_email = "devops-prod@gitea.local"
  alert_slack = "#infrastructure-alerts"
  log_level   = "WARNING"

  # SLA monitoring
  uptime_check_enabled = true
  sla_target = 99.9

  # Backup Settings (comprehensive)
  backup_enabled = true
  backup_schedule = "0 2,14 * * *"  # Twice daily
  retention_days = 30

  # Point-in-time recovery
  pitr_enabled = true
  pitr_retention_days = 7

  # Disaster Recovery
  dr_region = "us-east1"
  dr_enabled = true

  # Audit and Compliance
  audit_log_retention = 365
  enable_data_access_logs = true
  enable_admin_activity_logs = true
  enable_system_event_logs = true

  # Change Management
  maintenance_window = {
    day_of_week = 7  # Sunday
    hour       = 3   # 3 AM
    duration   = "4h"
  }
}