package = "kong-plugin-statsd-advanced"
<<<<<<<< HEAD:plugins-ee/statsd-advanced/kong-plugin-statsd-advanced-0.3.3-0.rockspec
version = "0.3.3-0"

source = {
  url = "https://github.com/Kong/kong-plugin-statsd-advanced",
  tag = "0.3.3"
========
version = "3.0.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-statsd-advanced",
  tag = "3.0.0"
>>>>>>>> ea820bb8a (feat(plugins-ee) update enterprise plugins to version 3.0.0):plugins-ee/statsd-advanced/kong-plugin-statsd-advanced-3.0.0-0.rockspec
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
