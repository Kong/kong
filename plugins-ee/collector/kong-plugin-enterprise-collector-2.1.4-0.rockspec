package = "kong-plugin-enterprise-collector"
version = "2.1.4-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-brain",
  tag = "2.1.4"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong enterprise plugin to send data to Kong Immunity",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.collector.api"]     = "kong/plugins/collector/api.lua",
    ["kong.plugins.collector.backend"] = "kong/plugins/collector/backend.lua",
    ["kong.plugins.collector.handler"] = "kong/plugins/collector/handler.lua",
    ["kong.plugins.collector.schema"]  = "kong/plugins/collector/schema.lua",
  }
}
