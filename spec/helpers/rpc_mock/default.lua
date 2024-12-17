local default_cert = {
  cluster_mtls = "shared",
  cluster_cert = "spec/fixtures/kong_clustering.crt",
  cluster_cert_key = "spec/fixtures/kong_clustering.key",
  nginx_conf = "spec/fixtures/custom_nginx.template",
}

return {
  default_cert = default_cert,
}
