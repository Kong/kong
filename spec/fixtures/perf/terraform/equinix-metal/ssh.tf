resource "local_file" "key_priv" {
  content  = tls_private_key.key.private_key_pem
  filename = "./id_rsa"
}

resource "null_resource" "key_chown" {
  provisioner "local-exec" {
    command = "chmod 400 ./id_rsa"
  }

  depends_on = [local_file.key_priv]
}

