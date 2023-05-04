package = "kong-plugin-enterprise-route-by-header"
version = "3.4.0-0"

supported_platforms = {"linux", "macosx"}
source = {
  url = "http://github.com/Kong/kong-plugin-enterprise-route-by-header.git",
  tag = "3.4.0"
}

description = {
  summary = "Kong plugin to route requests based on set header's value",
  homepage = "http://getkong.org",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.route-by-header.handler"] = "kong/plugins/route-by-header/handler.lua",
    ["kong.plugins.route-by-header.schema"] = "kong/plugins/route-by-header/schema.lua",
  }
}
