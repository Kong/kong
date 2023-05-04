package = "kong-plugin-enterprise-forward-proxy"
version = "3.4.0-0"

source = {
  url = "https://github.com/Mashape/kong-plugin-enterprise-forward-proxy",
  tag = "3.4.0"
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
