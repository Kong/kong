package = "kong-plugin-enterprise-openid-connect"
version = "dev-0"

source = {
  url = "git://github.com/Kong/kong-plugin-enterprise-openid-connect.git",
  tag = "dev",
}

description = {
  summary    = "Kong OpenID Connect Plugin",
  detailed   = "Kong OpenID Connect 1.0 plugin for integrating with 3rd party identity providers.",
  homepage   = "https://github.com/Kong/kong-plugin-enterprise-openid-connect",
  maintainer = "Aapo Talvensaari <bungle@konghq.com>",
}

dependencies = {
  "lua >= 5.1",
  "lua-resty-session >= 3.10",
  "lua-resty-http >= 0.15",
  "kong-openid-connect == 2.6.0-1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.openid-connect.api"] =
     "kong/plugins/openid-connect/api.lua",

    ["kong.plugins.openid-connect.arguments"] =
     "kong/plugins/openid-connect/arguments.lua",

    ["kong.plugins.openid-connect.cache"] =
     "kong/plugins/openid-connect/cache.lua",

    ["kong.plugins.openid-connect.claims"] =
     "kong/plugins/openid-connect/claims.lua",

    ["kong.plugins.openid-connect.clients"] =
     "kong/plugins/openid-connect/clients.lua",

    ["kong.plugins.openid-connect.consumers"] =
     "kong/plugins/openid-connect/consumers.lua",

    ["kong.plugins.openid-connect.handler"] =
     "kong/plugins/openid-connect/handler.lua",

    ["kong.plugins.openid-connect.headers"] =
     "kong/plugins/openid-connect/headers.lua",

    ["kong.plugins.openid-connect.introspect"] =
     "kong/plugins/openid-connect/introspect.lua",

    ["kong.plugins.openid-connect.log"] =
     "kong/plugins/openid-connect/log.lua",

    ["kong.plugins.openid-connect.responses"] =
     "kong/plugins/openid-connect/responses.lua",

    ["kong.plugins.openid-connect.redirect"] =
     "kong/plugins/openid-connect/redirect.lua",

    ["kong.plugins.openid-connect.schema"] =
     "kong/plugins/openid-connect/schema.lua",

    ["kong.plugins.openid-connect.sessions"] =
     "kong/plugins/openid-connect/sessions.lua",

    ["kong.plugins.openid-connect.typedefs"] =
     "kong/plugins/openid-connect/typedefs.lua",

    ["kong.plugins.openid-connect.unexpected"] =
     "kong/plugins/openid-connect/unexpected.lua",

    ["kong.plugins.openid-connect.userinfo"] =
     "kong/plugins/openid-connect/userinfo.lua",

    ["kong.plugins.openid-connect.daos"] =
     "kong/plugins/openid-connect/daos/init.lua",

    ["kong.plugins.openid-connect.daos.jwks"] =
     "kong/plugins/openid-connect/daos/jwks.lua",

    ["kong.plugins.openid-connect.migrations"] =
     "kong/plugins/openid-connect/migrations/init.lua",

    ["kong.plugins.openid-connect.migrations.000_base_openid_connect"] =
     "kong/plugins/openid-connect/migrations/000_base_openid_connect.lua",

    ["kong.plugins.openid-connect.migrations.001_14_to_15"] =
     "kong/plugins/openid-connect/migrations/001_14_to_15.lua",

    ["kong.plugins.openid-connect.migrations.002_200_to_210"] =
     "kong/plugins/openid-connect/migrations/002_200_to_210.lua",

     ["kong.plugins.openid-connect.migrations.003_280_to_300"] =
      "kong/plugins/openid-connect/migrations/003_280_to_300.lua",
  },
}
