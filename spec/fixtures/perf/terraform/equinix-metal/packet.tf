resource "packet_ssh_key" "key" {
  name       = "key1"
  public_key = tls_private_key.key.public_key_openssh
}

resource "packet_device" "kong" {
  hostname         = "kong-test-${random_string.ident.result}"
  plan             = var.packet_plan
  facilities       = [var.packet_region]
  operating_system = var.packet_os
  billing_cycle    = "hourly"
  project_id       = var.packet_project_id
  depends_on = [
    packet_ssh_key.key,
    null_resource.key_chown,
  ]
}

resource "packet_device" "worker" {
  hostname         = "worker-${random_string.ident.result}"
  plan             = var.packet_plan
  facilities       = [var.packet_region]
  operating_system = var.packet_os
  billing_cycle    = "hourly"
  project_id       = var.packet_project_id
  depends_on = [
    packet_ssh_key.key,
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

