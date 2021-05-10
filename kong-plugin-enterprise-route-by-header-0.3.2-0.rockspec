package = "kong-plugin-enterprise-route-by-header"
version = "0.3.2-0"

local pluginName = package:match("^kong%-plugin%-enterprise%-(.+)$")

supported_platforms = {"linux", "macosx"}
source = {
  url = "http://github.com/Kong/kong-plugin-enterprise-route-by-header.git",
  tag = "0.3.2"
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
    ["kong.plugins."..pluginName..".handler"] = "kong/plugins/"..pluginName.."/handler.lua",
    ["kong.plugins."..pluginName..".schema"] = "kong/plugins/"..pluginName.."/schema.lua",
  }
}
