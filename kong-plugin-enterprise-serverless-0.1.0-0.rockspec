package = "kong-plugin-enterprise-serverless"
version = "0.1.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-serverless",
  tag = "0.1.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Serverless plugins for Kong APIs",
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
