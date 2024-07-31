package = "kong-plugin-header-cert-auth"
version = "dev-0"

source = {
  url = "https://github.com/kong/kong-plugin-header-cert-auth",
  tag = "dev"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong plugin to authenticate using client certificate header.",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.header-cert-auth.daos"] = "kong/plugins/header-cert-auth/daos.lua",
    ["kong.plugins.header-cert-auth.handler"] = "kong/plugins/header-cert-auth/handler.lua",
    ["kong.plugins.header-cert-auth.schema"] = "kong/plugins/header-cert-auth/schema.lua",
    ["kong.plugins.header-cert-auth.migrations"] = "kong/plugins/header-cert-auth/migrations/init.lua",
    ["kong.plugins.header-cert-auth.migrations.000_base_header_cert_auth"] = "kong/plugins/header-cert-auth/migrations/000_base_header_cert_auth.lua",
    ["kong.plugins.header-cert-auth.cache"] = "kong/plugins/header-cert-auth/cache.lua",
    ["kong.plugins.header-cert-auth.access"] = "kong/plugins/header-cert-auth/access.lua",
    ["kong.plugins.header-cert-auth.api"] = "kong/plugins/header-cert-auth/api.lua",
    ["kong.plugins.header-cert-auth.ocsp_client"] = "kong/plugins/header-cert-auth/ocsp_client.lua",
    ["kong.plugins.header-cert-auth.crl_client"] = "kong/plugins/header-cert-auth/crl_client.lua",
  }
}
