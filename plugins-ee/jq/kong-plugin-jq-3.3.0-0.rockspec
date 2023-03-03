package = "kong-plugin-jq"
version = "3.3.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-jq",
  tag = "3.3.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Enterprise jq plugin"
}

dependencies = {
	"lua-resty-jq == 0.1.0",
	"lua == 5.1", -- Really "luajit >= 2.0.2"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.jq.cache"] = "kong/plugins/jq/cache.lua",
    ["kong.plugins.jq.handler"] = "kong/plugins/jq/handler.lua",
    ["kong.plugins.jq.schema"] = "kong/plugins/jq/schema.lua",
    ["kong.plugins.jq.typedefs"] = "kong/plugins/jq/typedefs.lua",
  }
}
