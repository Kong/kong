package = "kong-plugin-upstream-timeout"
version = "0.1.1-0"

source = {
  url = "https://github.com/Kong/upstream-timeout.git"
}

description = {
  summary = "Kong Upstream Timeout Plugin"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.upstream-timeout.handler"] = "kong/plugins/upstream-timeout/handler.lua",
    ["kong.plugins.upstream-timeout.schema"] = "kong/plugins/upstream-timeout/schema.lua"
  }
}
