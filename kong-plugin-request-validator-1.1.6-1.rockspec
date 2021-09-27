package = "kong-plugin-request-validator"
version = "1.1.6-1"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-request-validator",
  tag = "1.1.6"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "HTTP Request Validator for Kong Enterprise",
}

dependencies = {
  "lua-resty-ljsonschema == 1.1.2",
  "lua-resty-openapi3-deserializer == 1.2.0",
}

build = {
  type = "builtin",
  modules = {
    -- base plugin files
    ["kong.plugins.request-validator.handler"]         = "kong/plugins/request-validator/handler.lua",
    ["kong.plugins.request-validator.schema"]          = "kong/plugins/request-validator/schema.lua",

    -- Validator files for version: "kong" (build in Kong schema's)
    ["kong.plugins.request-validator.kong.init"]       = "kong/plugins/request-validator/kong/init.lua",
    ["kong.plugins.request-validator.kong.metaschema"] = "kong/plugins/request-validator/kong/metaschema.lua",

    -- Validator files for version: "draft4" (JSONschema draft 4)
    ["kong.plugins.request-validator.draft4.init"]     = "kong/plugins/request-validator/draft4/init.lua",
  }
}
