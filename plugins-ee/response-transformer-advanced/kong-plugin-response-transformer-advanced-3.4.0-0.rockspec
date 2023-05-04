package = "kong-plugin-response-transformer-advanced"
version = "3.4.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-response-transformer-advanced",
  tag = "3.4.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Response Transformer Advanced Plugin",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.response-transformer-advanced.migrations.enterprise"] = "kong/plugins/response-transformer-advanced/migrations/enterprise/init.lua",
    ["kong.plugins.response-transformer-advanced.migrations.enterprise.001_1500_to_2100"] = "kong/plugins/response-transformer-advanced/migrations/enterprise/001_1500_to_2100.lua",
    ["kong.plugins.response-transformer-advanced.handler"] = "kong/plugins/response-transformer-advanced/handler.lua",
    ["kong.plugins.response-transformer-advanced.body_transformer"] = "kong/plugins/response-transformer-advanced/body_transformer.lua",
    ["kong.plugins.response-transformer-advanced.header_transformer"] = "kong/plugins/response-transformer-advanced/header_transformer.lua",
    ["kong.plugins.response-transformer-advanced.schema"] = "kong/plugins/response-transformer-advanced/schema.lua",
    ["kong.plugins.response-transformer-advanced.feature_flags.limit_body"] = "kong/plugins/response-transformer-advanced/feature_flags/limit_body.lua",
    ["kong.plugins.response-transformer-advanced.transform_utils"] = "kong/plugins/response-transformer-advanced/transform_utils.lua",
    ["kong.plugins.response-transformer-advanced.constants"] = "kong/plugins/response-transformer-advanced/constants.lua",
  }
}
