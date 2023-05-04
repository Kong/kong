package = "kong-plugin-enterprise-canary"
version = "3.4.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-canary",
  tag = "3.4.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Canary release for Kong APIs",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.canary.handler"] = "kong/plugins/canary/handler.lua",
    ["kong.plugins.canary.schema"]  = "kong/plugins/canary/schema.lua",
    ["kong.plugins.canary.groups"]  = "kong/plugins/canary/groups.lua",
    ["kong.plugins.canary.migrations"] = "kong/plugins/canary/migrations/init.lua",
    ["kong.plugins.canary.migrations.001_200_to_210"] = "kong/plugins/canary/migrations/001_200_to_210.lua",
  }
}
