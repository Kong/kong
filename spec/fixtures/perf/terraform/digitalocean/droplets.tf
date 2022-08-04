resource "digitalocean_ssh_key" "key" {
  name       = "key1"
  public_key = tls_private_key.key.public_key_openssh
}

resource "digitalocean_droplet" "kong" {
  name             = "kong-${random_string.ident.result}"
  size             = var.do_size
  region           = var.do_region
  image            = var.do_os
  ssh_keys         = [digitalocean_ssh_key.key.fingerprint]
}

resource "digitalocean_droplet" "db" {
  count            = var.seperate_db_node ? 1: 0
  name             = "db-${random_string.ident.result}"
  size             = var.do_db_size
  region           = var.do_region
  image            = var.do_os
  ssh_keys         = [digitalocean_ssh_key.key.fingerprint]
}

resource "digitalocean_droplet" "worker" {
  name             = "worker-${random_string.ident.result}"
  size             = var.do_worker_size
  region           = var.do_region
  image            = var.do_os
  ssh_keys         = [digitalocean_ssh_key.key.fingerprint]
}

resource "random_string" "ident" {
  length  = 4
  special = false
}
