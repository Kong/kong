package = "kong-plugin-request-transformer"
version = "1.3.2-0"

source = {
  url = "git://github.com/Kong/kong-plugin-request-transformer",
  tag = "1.3.2"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Request Transformer Plugin",
  license = "Apache 2.0",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.request-transformer.migrations.cassandra"] = "kong/plugins/request-transformer/migrations/cassandra.lua",
    ["kong.plugins.request-transformer.migrations.postgres"] = "kong/plugins/request-transformer/migrations/postgres.lua",
    ["kong.plugins.request-transformer.migrations.common"] = "kong/plugins/request-transformer/migrations/common.lua",
    ["kong.plugins.request-transformer.handler"] = "kong/plugins/request-transformer/handler.lua",
    ["kong.plugins.request-transformer.access"] = "kong/plugins/request-transformer/access.lua",
    ["kong.plugins.request-transformer.schema"] = "kong/plugins/request-transformer/schema.lua",
  }
}
