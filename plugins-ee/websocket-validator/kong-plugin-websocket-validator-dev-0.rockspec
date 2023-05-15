package = "kong-plugin-websocket-validator"
version = "dev-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-websocket-validator",
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "WebSocket Message Validator for Kong Enterprise",
}

dependencies = {}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.websocket-validator.handler"] = "kong/plugins/websocket-validator/handler.lua",
    ["kong.plugins.websocket-validator.schema"]  = "kong/plugins/websocket-validator/schema.lua",
  }
}
