output "kong-ip" {
  value = metal_device.kong.access_public_ipv4
}

output "kong-internal-ip" {
  value = metal_device.kong.access_private_ipv4
}

output "worker-ip" {
  value = metal_device.worker.access_public_ipv4
}

output "worker-internal-ip" {
  value = metal_device.worker.access_private_ipv4
}

