package = "kong-plugin-jwt-signer"
version = "dev-0"
source = {
  url = "git://github.com/Kong/kong-plugin-jwt-signer.git",
  tag = "dev"
}
description = {
  summary    = "Kong JWT Signer Plugin",
  detailed   = "Makes it possible to sign (or re-sign) JWT tokens with Kong.",
  homepage   = "https://github.com/Kong/kong-plugin-jwt-signer",
  maintainer = "Aapo Talvensaari <bungle@konghq.com>",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.jwt-signer.api"] =
     "kong/plugins/jwt-signer/api.lua",

    ["kong.plugins.jwt-signer.arguments"] =
     "kong/plugins/jwt-signer/arguments.lua",

    ["kong.plugins.jwt-signer.cache"] =
     "kong/plugins/jwt-signer/cache.lua",

    ["kong.plugins.jwt-signer.daos"] =
     "kong/plugins/jwt-signer/daos.lua",

    ["kong.plugins.jwt-signer.handler"] =
     "kong/plugins/jwt-signer/handler.lua",

    ["kong.plugins.jwt-signer.log"] =
     "kong/plugins/jwt-signer/log.lua",

    ["kong.plugins.jwt-signer.schema"] =
     "kong/plugins/jwt-signer/schema.lua",

    ["kong.plugins.jwt-signer.migrations"] =
     "kong/plugins/jwt-signer/migrations/init.lua",

    ["kong.plugins.jwt-signer.migrations.000_base_jwt_signer"] =
     "kong/plugins/jwt-signer/migrations/000_base_jwt_signer.lua",

    ["kong.plugins.jwt-signer.migrations.001_200_to_210"] =
     "kong/plugins/jwt-signer/migrations/001_200_to_210.lua",
  }
}
