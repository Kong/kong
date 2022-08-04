output "kong-ip" {
  value = digitalocean_droplet.kong.ipv4_address
}

output "kong-internal-ip" {
  value = digitalocean_droplet.kong.ipv4_address_private
}

output "db-ip" {
  value = var.seperate_db_node ? digitalocean_droplet.db.0.ipv4_address: ""
}

output "db-internal-ip" {
  value = var.seperate_db_node ? digitalocean_droplet.db.0.ipv4_address_private: ""
}

output "worker-ip" {
  value = digitalocean_droplet.worker.ipv4_address
}

output "worker-internal-ip" {
  value = digitalocean_droplet.worker.ipv4_address_private
}
