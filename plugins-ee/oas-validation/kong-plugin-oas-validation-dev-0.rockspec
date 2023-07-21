package = "kong-plugin-oas-validation"
version = "dev-0"

supported_platforms = {"linux", "macosx"}
source = {
  url = "",
  tag = "dev"
}

description = {
  summary = "OAS Validation plugin for Kong Enterprise",
}

dependencies = {
  "lua-resty-ljsonschema ~> 1", -- intentionally not pinned, so it will follow the pinned version in Kong-EE
  "lua-resty-openapi3-deserializer == 2.0.0",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.oas-validation.handler"] = "kong/plugins/oas-validation/handler.lua",
    ["kong.plugins.oas-validation.schema"] = "kong/plugins/oas-validation/schema.lua",
    ["kong.plugins.oas-validation.utils.validation"] = "kong/plugins/oas-validation/utils/validation.lua",
    ["kong.plugins.oas-validation.constants"] = "kong/plugins/oas-validation/constants.lua",
    ["kong.plugins.oas-validation.utils"] = "kong/plugins/oas-validation/utils.lua",
  }

}
