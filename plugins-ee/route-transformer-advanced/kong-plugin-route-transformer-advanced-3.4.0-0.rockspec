local plugin_name = "route-transformer-advanced"
local plugin_version = "3.4.0"
local rockspec_revision = "0"

package = "kong-plugin-" .. plugin_name
version = plugin_version .. "-" .. rockspec_revision

source = {
  url = "git://github.com/Kong/" .. package,
  tag = plugin_version
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Route Transformer Plugin",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins." .. plugin_name .. ".handler"] = "kong/plugins/" .. plugin_name .. "/handler.lua",
    ["kong.plugins." .. plugin_name .. ".schema"] = "kong/plugins/" .. plugin_name .. "/schema.lua",
  }
}
