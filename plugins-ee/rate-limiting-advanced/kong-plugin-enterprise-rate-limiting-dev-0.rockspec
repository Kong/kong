package = "kong-plugin-enterprise-rate-limiting"
version = "dev-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-rate-limiting",
  tag = "dev"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Enterprise Rate Limiting",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.rate-limiting-advanced.handler"] = "kong/plugins/rate-limiting-advanced/handler.lua",
    ["kong.plugins.rate-limiting-advanced.schema"] = "kong/plugins/rate-limiting-advanced/schema.lua",
    ["kong.plugins.rate-limiting-advanced.migrations.001_370_to_380"] = "kong/plugins/rate-limiting-advanced/migrations/001_370_to_380.lua",
  }
}
