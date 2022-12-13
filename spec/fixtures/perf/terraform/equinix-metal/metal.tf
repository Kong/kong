resource "equinix_metal_ssh_key" "key" {
  name       = "key1"
  public_key = tls_private_key.key.public_key_openssh
}

resource "equinix_metal_device" "kong" {
  hostname         = "kong-${random_string.ident.result}"
  plan             = var.metal_plan
  facilities       = var.metal_region
  operating_system = var.metal_os
  billing_cycle    = "hourly"
  project_id       = var.metal_project_id
  tags             = []
  depends_on = [
    equinix_metal_ssh_key.key,
  ]
}

resource "equinix_metal_device" "db" {
  count            = var.seperate_db_node ? 1: 0
  hostname         = "db-${random_string.ident.result}"
  plan             = var.metal_db_plan
  facilities       = var.metal_region
  operating_system = var.metal_os
  billing_cycle    = "hourly"
  project_id       = var.metal_project_id
  tags             = []
  depends_on = [
    equinix_metal_ssh_key.key,
  ]
}

resource "equinix_metal_device" "worker" {
  hostname         = "worker-${random_string.ident.result}"
  plan             = var.metal_worker_plan
  facilities       = var.metal_region
  operating_system = var.metal_os
  billing_cycle    = "hourly"
  project_id       = var.metal_project_id
  tags             = []
  depends_on = [
    equinix_metal_ssh_key.key,
  ]
}

resource "random_string" "ident" {
  length  = 4
  special = false
}
