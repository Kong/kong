package = "kong-plugin-enterprise-ai-rate-limiting"
version = "dev-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-ai-rate-limiting",
  tag = "dev"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Enterprise AI Rate Limiting",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.ai-rate-limiting-advanced.handler"] = "kong/plugins/ai-rate-limiting-advanced/handler.lua",
    ["kong.plugins.ai-rate-limiting-advanced.schema"] = "kong/plugins/ai-rate-limiting-advanced/schema.lua",
  }
}