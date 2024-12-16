local default_cert = {
  cluster_mtls = "shared",
  clustetr_ca_cert = "path/kong_clustering_ca.crt",
  cluster_cert = "spec/fixtures/kong_clustering.crt",
  cluster_cert_key = "spec/fixtures/kong_clustering.key",
}

local default_cert_meta = { __index = default_cert, }

return {
  default_cert = default_cert,
  default_cert_meta = default_cert_meta,
}
