package = "kong-plugin-jq"
version = "0.0.1-0"

source = {
  url = "https://github.com/Kong/kong-plugin-jq",
  tag = "0.0.1"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Enterprise jq filter"
}

dependencies = {
	"lua-resty-jq ~> 0.0.2",
	"lua == 5.1", -- Really "luajit >= 2.0.2"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.jq-filter.cache"] = "kong/plugins/jq-filter/cache.lua",
    ["kong.plugins.jq-filter.handler"] = "kong/plugins/jq-filter/handler.lua",
    ["kong.plugins.jq-filter.schema"] = "kong/plugins/jq-filter/schema.lua",
    ["kong.plugins.jq-filter.typedefs"] = "kong/plugins/jq-filter/typedefs.lua",
  }
}
