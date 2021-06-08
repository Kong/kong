output "kong-ip" {
  value = packet_device.kong.access_public_ipv4
}

output "kong-internal-ip" {
  value = packet_device.kong.access_private_ipv4
}

output "worker-ip" {
  value = packet_device.worker.access_public_ipv4
}

output "worker-internal-ip" {
  value = packet_device.worker.access_private_ipv4
}

