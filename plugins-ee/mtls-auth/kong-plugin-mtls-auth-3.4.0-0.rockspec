package = "kong-plugin-mtls-auth"
version = "3.4.0-0"

source = {
  url = "https://github.com/kong/kong-plugin-mtls-auth",
  tag = "3.4.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Downstream mtls support for Kong",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.mtls-auth.daos"] = "kong/plugins/mtls-auth/daos.lua",
    ["kong.plugins.mtls-auth.handler"] = "kong/plugins/mtls-auth/handler.lua",
    ["kong.plugins.mtls-auth.schema"] = "kong/plugins/mtls-auth/schema.lua",
    ["kong.plugins.mtls-auth.migrations"] = "kong/plugins/mtls-auth/migrations/init.lua",
    ["kong.plugins.mtls-auth.migrations.000_base_mtls_auth"] = "kong/plugins/mtls-auth/migrations/000_base_mtls_auth.lua",
    ["kong.plugins.mtls-auth.migrations.001_200_to_210"] = "kong/plugins/mtls-auth/migrations/001_200_to_210.lua",
    ["kong.plugins.mtls-auth.migrations.002_2200_to_2300"] = "kong/plugins/mtls-auth/migrations/002_2200_to_2300.lua",
    ["kong.plugins.mtls-auth.migrations.enterprise"] = "kong/plugins/mtls-auth/migrations/enterprise/init.lua",
    ["kong.plugins.mtls-auth.migrations.enterprise.001_1500_to_2100"] = "kong/plugins/mtls-auth/migrations/enterprise/001_1500_to_2100.lua",
    ["kong.plugins.mtls-auth.migrations.enterprise.002_2200_to_2300"] = "kong/plugins/mtls-auth/migrations/enterprise/002_2200_to_2300.lua",
    ["kong.plugins.mtls-auth.cache"] = "kong/plugins/mtls-auth/cache.lua",
    ["kong.plugins.mtls-auth.access"] = "kong/plugins/mtls-auth/access.lua",
    ["kong.plugins.mtls-auth.api"] = "kong/plugins/mtls-auth/api.lua",
    ["kong.plugins.mtls-auth.ocsp_client"] = "kong/plugins/mtls-auth/ocsp_client.lua",
    ["kong.plugins.mtls-auth.crl_client"] = "kong/plugins/mtls-auth/crl_client.lua",
  }
}
