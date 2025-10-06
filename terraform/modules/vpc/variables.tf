# VPC Module - Variables
# CMMC 2.0: CM.L2-3.4.2 (Baseline Configuration)

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "auto_create_subnetworks" {
  description = "Auto-create subnetworks"
  type        = bool
  default     = false
}

variable "routing_mode" {
  description = "Network routing mode (REGIONAL or GLOBAL)"
  type        = string
  default     = "REGIONAL"
}

variable "mtu" {
  description = "Maximum Transmission Unit in bytes"
  type        = number
  default     = 1460
}

variable "subnets" {
  description = "List of subnet configurations"
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
    description   = optional(string)
  }))
}

variable "secondary_ranges" {
  description = "Secondary ranges for subnets"
  type = map(list(object({
    range_name    = string
    ip_cidr_range = string
  })))
  default = {}
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access"
  type        = bool
  default     = true
}

variable "enable_private_ipv6_google_access" {
  description = "Enable Private IPv6 Google Access"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_logs_config" {
  description = "Flow logs configuration"
  type = object({
    aggregation_interval = optional(string)
    flow_sampling       = optional(number)
    metadata           = optional(string)
    metadata_fields    = optional(list(string))
    filter_expr        = optional(string)
  })
  default = {}
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT"
  type        = bool
  default     = true
}

variable "nat_name" {
  description = "Name of the Cloud NAT"
  type        = string
  default     = ""
}

variable "nat_ip_allocate_option" {
  description = "NAT IP allocation option (AUTO_ONLY or MANUAL_ONLY)"
  type        = string
  default     = "AUTO_ONLY"
}

variable "nat_ip_count" {
  description = "Number of NAT IPs to allocate (for MANUAL_ONLY)"
  type        = number
  default     = 1
}

variable "nat_log_enabled" {
  description = "Enable NAT logging"
  type        = bool
  default     = false
}

variable "advertised_ip_ranges" {
  description = "IP ranges to advertise via Cloud Router"
  type        = list(string)
  default     = []
}

variable "firewall_rules" {
  description = "Map of firewall rules"
  type = map(object({
    description             = string
    direction              = string
    priority               = number
    ranges                 = optional(list(string))
    source_tags            = optional(list(string))
    target_tags            = optional(list(string))
    source_service_accounts = optional(list(string))
    target_service_accounts = optional(list(string))
    allow = optional(list(object({
      protocol = string
      ports    = list(string)
    })))
    deny = optional(list(object({
      protocol = string
      ports    = list(string)
    })))
    disabled      = optional(bool)
    enable_logging = optional(bool)
  }))
  default = {}
}

variable "custom_firewall_rules" {
  description = "Custom firewall rules for specific environments"
  type = map(object({
    description = string
    direction   = string
    priority    = number
    ranges      = list(string)
    protocol    = string
    ports       = list(string)
    target_tags = optional(list(string))
  }))
  default = {}
}

variable "enable_private_service_connection" {
  description = "Enable Private Service Connection for Google services"
  type        = bool
  default     = false
}

variable "enable_dns_managed_zone" {
  description = "Create a private DNS managed zone"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Name of the DNS managed zone"
  type        = string
  default     = ""
}

variable "dns_zone_dns_name" {
  description = "DNS name of the managed zone"
  type        = string
  default     = ""
}

variable "enable_vpc_service_controls" {
  description = "Enable VPC Service Controls"
  type        = bool
  default     = false
}

variable "access_context_policy" {
  description = "Access Context Manager policy ID"
  type        = string
  default     = ""
}

variable "vpc_sc_perimeter_name" {
  description = "VPC Service Controls perimeter name"
  type        = string
  default     = ""
}

variable "vpc_sc_resources" {
  description = "Resources to include in VPC Service Controls perimeter"
  type        = list(string)
  default     = []
}

variable "vpc_sc_allowed_services" {
  description = "Services allowed in VPC Service Controls"
  type        = list(string)
  default     = []
}

variable "vpc_sc_ingress_policies" {
  description = "VPC Service Controls ingress policies"
  type = list(object({
    identities = list(string)
    resource   = string
    service    = string
    method     = string
  }))
  default = []
}

variable "vpc_sc_egress_policies" {
  description = "VPC Service Controls egress policies"
  type = list(object({
    identities = list(string)
    resources  = list(string)
    service    = string
    method     = string
  }))
  default = []
}

variable "network_peerings" {
  description = "Network peering configurations"
  type = map(object({
    peer_network         = string
    export_custom_routes = optional(bool)
    import_custom_routes = optional(bool)
  }))
  default = {}
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}