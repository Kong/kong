package = "kong-plugin-statsd-advanced"
version = "0.2.3-0"

source = {
  url = "https://github.com/Kong/kong-plugin-statsd-advanced",
  tag = "0.2.3"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "StatsD Advanced Plugin",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.statsd-advanced.handler"] = "kong/plugins/statsd-advanced/handler.lua",
    ["kong.plugins.statsd-advanced.schema"]  = "kong/plugins/statsd-advanced/schema.lua",
    ["kong.plugins.statsd-advanced.log_helper"]  = "kong/plugins/statsd-advanced/log_helper.lua",
    ["kong.plugins.statsd-advanced.constants"]  = "kong/plugins/statsd-advanced/constants.lua",
  }
}
