package = "kong-plugin-key-auth-enc"
version = "3.1.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-key-auth-enc",
  tag = "3.1.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "key-auth with symmetrically encrypted tokens",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.key-auth-enc.handler"]    = "kong/plugins/key-auth-enc/handler.lua",
    ["kong.plugins.key-auth-enc.schema"]     = "kong/plugins/key-auth-enc/schema.lua",
    ["kong.plugins.key-auth-enc.daos"]       = "kong/plugins/key-auth-enc/daos.lua",
    ["kong.plugins.key-auth-enc.keyauth_enc_credentials"] = "kong/plugins/key-auth-enc/keyauth_enc_credentials.lua",
    ["kong.plugins.key-auth-enc.migrations"] = "kong/plugins/key-auth-enc/migrations/init.lua",
    ["kong.plugins.key-auth-enc.migrations.000_base_key_auth_enc"] = "kong/plugins/key-auth-enc/migrations/000_base_key_auth_enc.lua",
    ["kong.plugins.key-auth-enc.migrations.001_200_to_210"] = "kong/plugins/key-auth-enc/migrations/001_200_to_210.lua",
    ["kong.plugins.key-auth-enc.migrations.enterprise"] = "kong/plugins/key-auth-enc/migrations/enterprise/init.lua",
    ["kong.plugins.key-auth-enc.migrations.enterprise.001_1500_to_2100"] = "kong/plugins/key-auth-enc/migrations/enterprise/001_1500_to_2100.lua",
    ["kong.plugins.key-auth-enc.migrations.enterprise.002_3100_to_3200"] = "kong/plugins/key-auth-enc/migrations/enterprise/002_3100_to_3200.lua",
    ["kong.plugins.key-auth-enc.migrations.enterprise.002_2800_to_3200"] = "kong/plugins/key-auth-enc/migrations/enterprise/002_2800_to_3200.lua",
    ["kong.plugins.key-auth-enc.strategies.postgres.keyauth_enc_credentials"] = "kong/plugins/key-auth-enc/strategies/postgres/keyauth_enc_credentials.lua",
    ["kong.plugins.key-auth-enc.strategies.cassandra.keyauth_enc_credentials"] = "kong/plugins/key-auth-enc/strategies/cassandra/keyauth_enc_credentials.lua",
    ["kong.plugins.key-auth-enc.strategies.off.keyauth_enc_credentials"] = "kong/plugins/key-auth-enc/strategies/off/keyauth_enc_credentials.lua",
  }
}
