# copy the file to current directory to be loaded by framework
resource "local_sensitive_file" "key_priv" {
  source  = var.ssh_key_path
  filename = "./id_rsa"
  file_permission = "0600"
}