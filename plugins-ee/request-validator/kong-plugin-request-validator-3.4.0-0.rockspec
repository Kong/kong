package = "kong-plugin-request-validator"
version = "3.4.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-request-validator",
  tag = "3.4.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "HTTP Request Validator for Kong Enterprise",
}

dependencies = {
  "lua-resty-openapi3-deserializer == 2.0.0",
}

build = {
  type = "builtin",
  modules = {
    -- base plugin files
    ["kong.plugins.request-validator.handler"]         = "kong/plugins/request-validator/handler.lua",
    ["kong.plugins.request-validator.schema"]          = "kong/plugins/request-validator/schema.lua",
    ["kong.plugins.request-validator.validators"]      = "kong/plugins/request-validator/validators.lua",

    -- Validator files for version: "kong" (build in Kong schema's)
    ["kong.plugins.request-validator.kong.init"]       = "kong/plugins/request-validator/kong/init.lua",
    ["kong.plugins.request-validator.kong.metaschema"] = "kong/plugins/request-validator/kong/metaschema.lua",
  }
}
