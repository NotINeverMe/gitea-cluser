# VPC Module - Outputs

output "network_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "VPC network self link"
  value       = google_compute_network.vpc.self_link
}

output "subnets" {
  description = "Map of subnet names to subnet info"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => {
      name          = v.name
      id            = v.id
      self_link     = v.self_link
      ip_range      = v.ip_cidr_range
      region        = v.region
      gateway_address = v.gateway_address
    }
  }
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = [for s in google_compute_subnetwork.subnets : s.id]
}

output "subnet_self_links" {
  description = "List of subnet self links"
  value       = [for s in google_compute_subnetwork.subnets : s.self_link]
}

output "subnet_secondary_ranges" {
  description = "Map of subnet secondary ranges"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => [
      for sr in v.secondary_ip_range : {
        range_name = sr.range_name
        ip_range   = sr.ip_cidr_range
      }
    ]
  }
}

output "router_id" {
  description = "Cloud Router ID"
  value       = var.enable_cloud_nat ? google_compute_router.router[0].id : null
}

output "router_name" {
  description = "Cloud Router name"
  value       = var.enable_cloud_nat ? google_compute_router.router[0].name : null
}

output "nat_id" {
  description = "Cloud NAT ID"
  value       = var.enable_cloud_nat ? google_compute_router_nat.nat[0].id : null
}

output "nat_ips" {
  description = "Cloud NAT IP addresses"
  value       = var.nat_ip_allocate_option == "MANUAL_ONLY" ? [for ip in google_compute_address.nat_ips : ip.address] : []
}

output "firewall_rules" {
  description = "Map of firewall rule names to IDs"
  value = {
    for k, v in google_compute_firewall.rules : k => v.id
  }
}

output "private_service_connection_ip" {
  description = "Private service connection IP range"
  value       = var.enable_private_service_connection ? google_compute_global_address.private_service_connection[0].address : null
}

output "dns_zone_name" {
  description = "DNS managed zone name"
  value       = var.enable_dns_managed_zone ? google_dns_managed_zone.private_zone[0].name : null
}

output "dns_zone_dns_name" {
  description = "DNS managed zone DNS name"
  value       = var.enable_dns_managed_zone ? google_dns_managed_zone.private_zone[0].dns_name : null
}

output "vpc_sc_perimeter_name" {
  description = "VPC Service Controls perimeter name"
  value       = var.enable_vpc_service_controls ? google_access_context_manager_service_perimeter.vpc_sc[0].name : null
}