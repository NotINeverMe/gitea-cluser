# Monitoring and Alerting Configuration for Gitea GCP Deployment
# CMMC 2.0 Level 2 Monitoring Controls
# NIST SP 800-171 Rev. 2 SI.L2-3.14.1: System Monitoring

# ============================================================================
# NOTIFICATION CHANNELS - SI.L2-3.14.1: Information System Monitoring
# ============================================================================

# Email notification channel
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0

  display_name = "Email Alert Channel"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  user_labels = merge(local.common_labels, {
    "purpose"      = "alerts"
    "cmmc-control" = "si-l2-3-14-1"
  })
}

# Slack notification channel (optional)
resource "google_monitoring_notification_channel" "slack" {
  count = 0  # Enable if Slack webhook is configured

  display_name = "Slack Alert Channel"
  type         = "slack"

  labels = {
    channel_name = "#gitea-alerts"
    url          = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  }

  user_labels = merge(local.common_labels, {
    "purpose" = "alerts"
  })

  sensitive_labels {
    auth_token = "YOUR_SLACK_TOKEN"
  }
}

# PagerDuty notification channel (optional)
resource "google_monitoring_notification_channel" "pagerduty" {
  count = 0  # Enable if PagerDuty is configured

  display_name = "PagerDuty Alert Channel"
  type         = "pagerduty"

  labels = {
    service_key = "YOUR_PAGERDUTY_SERVICE_KEY"
  }

  user_labels = merge(local.common_labels, {
    "purpose" = "critical-alerts"
  })
}

# ============================================================================
# UPTIME CHECKS - SI.L2-3.14.2: System Monitoring
# ============================================================================

# HTTPS uptime check for Gitea
resource "google_monitoring_uptime_check_config" "gitea_https" {
  count = var.enable_uptime_checks ? 1 : 0

  display_name = "${local.name_prefix}-https-uptime"
  timeout      = "30s"
  period       = "60s"  # Check every minute

  http_check {
    path         = "/api/v1/version"  # Gitea API endpoint
    port         = "443"
    use_ssl      = true
    validate_ssl = true

    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = var.project_id
      host       = var.gitea_domain
    }
  }

  content_matchers {
    content = "\"version\""
    matcher = "CONTAINS_STRING"
  }

  selected_regions = [
    "USA",
    "EUROPE",
    "ASIA_PACIFIC"
  ]

  user_labels = merge(local.common_labels, {
    "service"      = "gitea"
    "cmmc-control" = "si-l2-3-14-2"
  })
}

# TCP uptime check for Git SSH
resource "google_monitoring_uptime_check_config" "git_ssh" {
  count = var.enable_uptime_checks && length(var.allowed_git_ssh_cidr_ranges) > 0 ? 1 : 0

  display_name = "${local.name_prefix}-git-ssh-uptime"
  timeout      = "10s"
  period       = "300s"  # Check every 5 minutes

  tcp_check {
    port = 10001  # Custom Git SSH port
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = var.project_id
      host       = google_compute_address.gitea_ip.address
    }
  }

  selected_regions = [
    "USA"
  ]

  user_labels = merge(local.common_labels, {
    "service" = "git-ssh"
  })
}

# ============================================================================
# ALERT POLICIES - SI.L2-3.14.3: Security Alerts
# ============================================================================

# Alert for instance down
resource "google_monitoring_alert_policy" "instance_down" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${local.name_prefix}-instance-down"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "VM Instance is down"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/uptime\""
      duration        = "60s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content   = "The Gitea instance ${local.instance_name} is down. Check the instance status in the GCP Console."
    mime_type = "text/markdown"
  }

  notification_channels = var.enable_monitoring && var.alert_email != "" ? [
    google_monitoring_notification_channel.email[0].id
  ] : []

  user_labels = merge(local.common_labels, {
    "severity"     = "critical"
    "cmmc-control" = "si-l2-3-14-3"
  })

  alert_strategy {
    auto_close = "604800s"  # 7 days

#     rate_limit {
#       period = "900s"  # 15 minutes
#     }
  }
}

# Alert for high CPU usage
resource "google_monitoring_alert_policy" "high_cpu" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${local.name_prefix}-high-cpu"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "CPU utilization > 85%"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.85

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"

        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.instance_id"]
      }
    }
  }

  documentation {
    content   = "CPU utilization for ${local.instance_name} has exceeded 85% for 5 minutes."
    mime_type = "text/markdown"
  }

  notification_channels = var.enable_monitoring && var.alert_email != "" ? [
    google_monitoring_notification_channel.email[0].id
  ] : []

  user_labels = merge(local.common_labels, {
    "severity" = "warning"
  })

  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
}

# Alert for high memory usage
resource "google_monitoring_alert_policy" "high_memory" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${local.name_prefix}-high-memory"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Memory utilization > 90%"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"gce_instance\"",
        "resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\"",
        "metric.type = \"agent.googleapis.com/memory/percent_used\"",
        "metric.labels.state = \"used\""
      ])
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 90

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  documentation {
    content   = "Memory usage for ${local.instance_name} has exceeded 90% for 5 minutes."
    mime_type = "text/markdown"
  }

  notification_channels = var.enable_monitoring && var.alert_email != "" ? [
    google_monitoring_notification_channel.email[0].id
  ] : []

  user_labels = merge(local.common_labels, {
    "severity" = "warning"
  })
}

# Alert for disk usage
resource "google_monitoring_alert_policy" "high_disk" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${local.name_prefix}-high-disk"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Boot disk usage > 80%"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"gce_instance\"",
        "resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\"",
        "metric.type = \"agent.googleapis.com/disk/percent_used\"",
        "metric.labels.device = \"/dev/sda1\""
      ])
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 80

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  conditions {
    display_name = "Data disk usage > 85%"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"gce_instance\"",
        "resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\"",
        "metric.type = \"agent.googleapis.com/disk/percent_used\"",
        "metric.labels.device = \"/dev/sdb\""
      ])
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 85

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  documentation {
    content   = "Disk usage for ${local.instance_name} is high. Consider expanding disk size or cleaning up old data."
    mime_type = "text/markdown"
  }

  notification_channels = var.enable_monitoring && var.alert_email != "" ? [
    google_monitoring_notification_channel.email[0].id
  ] : []

  user_labels = merge(local.common_labels, {
    "severity" = "warning"
  })
}

# Alert for uptime check failures
resource "google_monitoring_alert_policy" "uptime_failure" {
  count = var.enable_monitoring && var.enable_uptime_checks ? 1 : 0

  display_name = "${local.name_prefix}-uptime-failure"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Uptime check failure"

    condition_threshold {
      filter          = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.project_id"]
      }
    }
  }

  documentation {
    content   = "Gitea HTTPS endpoint is not responding. Check the service status immediately."
    mime_type = "text/markdown"
  }

  notification_channels = var.enable_monitoring && var.alert_email != "" ? [
    google_monitoring_notification_channel.email[0].id
  ] : []

  user_labels = merge(local.common_labels, {
    "severity"     = "critical"
    "cmmc-control" = "si-l2-3-14-1"
  })

  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
}

# Alert for security events (failed SSH attempts)
resource "google_monitoring_alert_policy" "security_ssh" {
  count = 0  # Disabled - requires log-based metric to be created first

  display_name = "${local.name_prefix}-security-ssh-attempts"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Multiple failed SSH attempts"

    condition_threshold {
      # Use log-based metric instead of regex filter (=~ not supported)
      filter = join(" AND ", [
        "resource.type = \"gce_instance\"",
        "metric.type = \"logging.googleapis.com/user/ssh_failed_attempts\""
      ])
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content   = "Multiple failed SSH attempts detected on ${local.instance_name}. Possible brute force attack."
    mime_type = "text/markdown"
  }

  notification_channels = var.enable_monitoring && var.alert_email != "" ? [
    google_monitoring_notification_channel.email[0].id
  ] : []

  user_labels = merge(local.common_labels, {
    "severity"     = "high"
    "type"         = "security"
    "cmmc-control" = "au-l2-3-3-1"
  })
}

# ============================================================================
# CUSTOM METRICS (OPTIONAL)
# ============================================================================

# Custom metric for Gitea repository count
resource "google_monitoring_metric_descriptor" "repo_count" {
  count = 0  # Enable if custom metrics are needed

  type         = "custom.googleapis.com/gitea/repository_count"
  display_name = "Gitea Repository Count"
  description  = "Total number of repositories in Gitea"

  metric_kind = "GAUGE"
  value_type  = "INT64"

  labels {
    key         = "organization"
    description = "Organization name"
  }

  labels {
    key         = "visibility"
    description = "Repository visibility (public/private)"
  }
}

# ============================================================================
# DASHBOARD - SI.L2-3.14.1: System Monitoring
# ============================================================================

resource "google_monitoring_dashboard" "gitea" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "${local.name_prefix}-dashboard"

    mosaicLayout = {
      columns = 12

      tiles = [
        # CPU Usage Chart
        {
          width  = 4
          height = 4
          widget = {
            title = "CPU Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },

        # Memory Usage Chart
        {
          width  = 4
          height = 4
          xPos   = 4
          widget = {
            title = "Memory Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\" AND metric.type = \"agent.googleapis.com/memory/percent_used\""
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },

        # Disk Usage Chart
        {
          width  = 4
          height = 4
          xPos   = 8
          widget = {
            title = "Disk Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\" AND metric.type = \"agent.googleapis.com/disk/percent_used\""
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },

        # Network Traffic
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "Network Traffic"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/network/received_bytes_count\""
                    }
                  }
                  plotType = "LINE"
                  legendTemplate = "Received"
                },
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.gitea_server.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/network/sent_bytes_count\""
                    }
                  }
                  plotType = "LINE"
                  legendTemplate = "Sent"
                }
              ]
            }
          }
        },

        # Uptime Status
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 4
          widget = {
            title = "Uptime Status"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\""
                  aggregation = {
                    alignmentPeriod = "60s"
                    perSeriesAligner = "ALIGN_FRACTION_TRUE"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        }
      ]
    }
  })
}

# ============================================================================
# LOG-BASED METRICS - AU.L2-3.3.1: Event Logging
# ============================================================================

# Log metric for tracking authentication failures
resource "google_logging_metric" "auth_failures" {
  count = var.enable_monitoring ? 1 : 0

  name        = "${local.name_prefix}-auth-failures"
  description = "Count of authentication failures"

  filter = "resource.type=\"gce_instance\" AND textPayload =~ \"authentication failure\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "severity"
      value_type  = "STRING"
      description = "Severity of the authentication failure"
    }
  }

  label_extractors = {
    severity = "EXTRACT(jsonPayload.severity)"
  }
}

# Log metric for tracking repository operations
resource "google_logging_metric" "repo_operations" {
  count = var.enable_monitoring ? 1 : 0

  name        = "${local.name_prefix}-repo-operations"
  description = "Count of repository operations"

  filter = "resource.type=\"gce_instance\" AND jsonPayload.operation =~ \"repo.*\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "operation"
      value_type  = "STRING"
      description = "Type of repository operation"
    }

    labels {
      key         = "user"
      value_type  = "STRING"
      description = "User performing the operation"
    }
  }

  label_extractors = {
    operation = "EXTRACT(jsonPayload.operation)"
    user      = "EXTRACT(jsonPayload.user)"
  }
}