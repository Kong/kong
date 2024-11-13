output "kong-ip" {
  value = var.kong_ip
}

output "kong-internal-ip" {
  value =  local.kong_internal_ip_fallback
}

output "db-ip" {
  value = var.db_ip
}

output "db-internal-ip" {
  value = var.db_internal_ip
}

output "worker-ip" {
  value = var.worker_ip
}

output "worker-internal-ip" {
  value = local.worker_internal_ip_fallback
}
