output "kong-ip" {
  value = digitalocean_droplet.kong.ipv4_address
}

output "kong-internal-ip" {
  value = digitalocean_droplet.kong.ipv4_address_private
}

output "db-ip" {
  value = digitalocean_droplet.db.ipv4_address
}

output "db-internal-ip" {
  value = digitalocean_droplet.db.ipv4_address_private
}

output "worker-ip" {
  value = digitalocean_droplet.worker.ipv4_address
}

output "worker-internal-ip" {
  value = digitalocean_droplet.worker.ipv4_address_private
}
