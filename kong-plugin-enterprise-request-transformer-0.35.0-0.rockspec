package = "kong-plugin-enterprise-request-transformer"
version = "0.35.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-request-transformer",
  tag = "0.35.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Enterprise Request Transformer",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.request-transformer-advanced.migrations.cassandra"] = "kong/plugins/request-transformer-advanced/migrations/cassandra.lua",
    ["kong.plugins.request-transformer-advanced.migrations.postgres"] = "kong/plugins/request-transformer-advanced/migrations/postgres.lua",
    ["kong.plugins.request-transformer-advanced.migrations.common"] = "kong/plugins/request-transformer-advanced/migrations/common.lua",
    ["kong.plugins.request-transformer-advanced.handler"] = "kong/plugins/request-transformer-advanced/handler.lua",
    ["kong.plugins.request-transformer-advanced.access"] = "kong/plugins/request-transformer-advanced/access.lua",
    ["kong.plugins.request-transformer-advanced.schema"] = "kong/plugins/request-transformer-advanced/schema.lua",
  }
}
