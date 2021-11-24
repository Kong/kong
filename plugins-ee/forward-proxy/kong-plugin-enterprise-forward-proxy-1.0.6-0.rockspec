package = "kong-plugin-enterprise-forward-proxy"
version = "1.0.6-0"

source = {
  url = "https://github.com/Mashape/kong-plugin-enterprise-forward-proxy",
  tag = "1.0.6"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Upstream HTTP Proxy support for Kong",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.forward-proxy.handler"] = "kong/plugins/forward-proxy/handler.lua",
    ["kong.plugins.forward-proxy.schema"]  = "kong/plugins/forward-proxy/schema.lua",
  }
}
