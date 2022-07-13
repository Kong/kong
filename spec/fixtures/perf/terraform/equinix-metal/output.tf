output "kong-ip" {
  value = equinix_metal_device.kong.access_public_ipv4
}

output "kong-internal-ip" {
  value = equinix_metal_device.kong.access_private_ipv4
}

output "db-ip" {
  value = equinix_metal_device.db.access_public_ipv4
}

output "db-internal-ip" {
  value = equinix_metal_device.db.access_private_ipv4
}

output "worker-ip" {
  value = equinix_metal_device.worker.access_public_ipv4
}

output "worker-internal-ip" {
  value = equinix_metal_device.worker.access_private_ipv4
}
