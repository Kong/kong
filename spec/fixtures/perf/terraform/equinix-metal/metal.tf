resource "metal_ssh_key" "key" {
  name       = "key1"
  public_key = tls_private_key.key.public_key_openssh
}

resource "metal_device" "kong" {
  hostname         = "kong-test-${random_string.ident.result}"
  plan             = var.metal_plan
  facilities       = [var.metal_region]
  operating_system = var.metal_os
  billing_cycle    = "hourly"
  project_id       = var.metal_project_id
  depends_on = [
    metal_ssh_key.key,
    null_resource.key_chown,
  ]
}

resource "metal_device" "worker" {
  hostname         = "worker-${random_string.ident.result}"
  plan             = var.metal_plan
  facilities       = [var.metal_region]
  operating_system = var.metal_os
  billing_cycle    = "hourly"
  project_id       = var.metal_project_id
  depends_on = [
    metal_ssh_key.key,
    null_resource.key_chown,
  ]

  provisioner "file" {
    connection {
      type        = "ssh"
      user        = "root"
      host        = self.access_public_ipv4
      private_key = file(local_file.key_priv.filename)
    }

    source      = "scripts/wrk.lua"
    destination = "/root/wrk.lua"
  }
}

resource "random_string" "ident" {
  length  = 4
  special = false
}

