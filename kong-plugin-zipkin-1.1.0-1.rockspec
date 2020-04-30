package = "kong-plugin-zipkin"
version = "1.1.0-1"

source = {
  url = "https://github.com/kong/kong-plugin-zipkin/archive/v1.1.0.zip",
  dir = "kong-plugin-zipkin-1.1.0",
}

description = {
  summary = "This plugin allows Kong to propagate Zipkin headers and report to a Zipkin server",
  homepage = "https://github.com/kong/kong-plugin-zipkin",
  license = "Apache 2.0",
}

dependencies = {
  "lua >= 5.1",
  "lua-cjson",
  "lua-resty-http >= 0.11",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.zipkin.handler"] = "kong/plugins/zipkin/handler.lua",
    ["kong.plugins.zipkin.reporter"] = "kong/plugins/zipkin/reporter.lua",
    ["kong.plugins.zipkin.span"] = "kong/plugins/zipkin/span.lua",
    ["kong.plugins.zipkin.tracing_headers"] = "kong/plugins/zipkin/tracing_headers.lua",
    ["kong.plugins.zipkin.schema"] = "kong/plugins/zipkin/schema.lua",
  },
}
