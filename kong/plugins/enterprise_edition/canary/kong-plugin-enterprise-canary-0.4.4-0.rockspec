package = "kong-plugin-enterprise-canary"
version = "0.4.4-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-canary",
  tag = "0.4.4"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Canary release for Kong APIs",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.canary.handler"] = "kong/plugins/enterprise_edition/canary/handler.lua",
    ["kong.plugins.canary.schema"]  = "kong/plugins/enterprise_edition/canary/schema.lua",
    ["kong.plugins.canary.groups"]  = "kong/plugins/enterprise_edition/canary/groups.lua",
    ["kong.plugins.canary.migrations"] = "kong/plugins/enterprise_edition/canary/migrations/init.lua",
    ["kong.plugins.canary.migrations.001_200_to_210"] = "kong/plugins/enterprise_edition/canary/migrations/001_200_to_210.lua",
  }
}
