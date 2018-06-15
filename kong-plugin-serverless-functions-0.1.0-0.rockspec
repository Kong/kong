package = "kong-plugin-serverless-functions"
version = "0.1.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-serverless-functions",
  tag = "0.1.0"
}

supported_platforms = {
  "linux",
  "macosx"
}

description = {
  summary = "Dynamically run Lua code from Kong during access phase.",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.pre-function.handler"] = "kong/plugins/pre-function/handler.lua",
    ["kong.plugins.pre-function.schema"] = "kong/plugins/pre-function/schema.lua",

    ["kong.plugins.post-function.handler"] = "kong/plugins/post-function/handler.lua",
    ["kong.plugins.post-function.schema"] = "kong/plugins/post-function/schema.lua",
  }
}
