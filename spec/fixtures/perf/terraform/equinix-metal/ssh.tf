resource "local_sensitive_file" "key_priv" {
  content  = tls_private_key.key.private_key_pem
  filename = "./id_rsa"
  file_permission = "0600"
}
