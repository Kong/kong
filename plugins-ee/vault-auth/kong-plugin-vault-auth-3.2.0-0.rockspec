package = "kong-plugin-vault-auth"
version = "3.2.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-vault-auth",
  tag = "3.2.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "A simple plugin to authenticate Consumers via Vault",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.vault-auth.handler"]    = "kong/plugins/vault-auth/handler.lua",
    ["kong.plugins.vault-auth.schema"]     = "kong/plugins/vault-auth/schema.lua",
    ["kong.plugins.vault-auth.daos"]       = "kong/plugins/vault-auth/daos.lua",
    ["kong.plugins.vault-auth.api"]        = "kong/plugins/vault-auth/api.lua",
    ["kong.plugins.vault-auth.vault-daos"] = "kong/plugins/vault-auth/vault-daos.lua",
    ["kong.plugins.vault-auth.vault"]      = "kong/plugins/vault-auth/vault.lua",
    ["kong.plugins.vault-auth.migrations"] = "kong/plugins/vault-auth/migrations/init.lua",
    ["kong.plugins.vault-auth.migrations.000_base_vault_auth"] = "kong/plugins/vault-auth/migrations/000_base_vault_auth.lua",
    ["kong.plugins.vault-auth.migrations.001_280_to_300"] = "kong/plugins/vault-auth/migrations/001_280_to_300.lua",
    ["kong.plugins.vault-auth.migrations.002_300_to_310"] = "kong/plugins/vault-auth/migrations/002_300_to_310.lua",
  }
}
