package = "kong-plugin-enterprise-forward-proxy"
version = "dev-0"

source = {
  url = "https://github.com/Mashape/kong-plugin-enterprise-forward-proxy",
  tag = "dev"
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
