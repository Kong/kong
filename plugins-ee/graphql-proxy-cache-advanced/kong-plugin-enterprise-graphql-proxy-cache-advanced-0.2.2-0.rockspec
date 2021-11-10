package = "kong-plugin-enterprise-graphql-proxy-cache-advanced"
version = "0.2.2-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-gql-proxy-cache",
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Enterprise Graphql Proxy Cache",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.graphql-proxy-cache-advanced.handler"] = "kong/plugins/graphql-proxy-cache-advanced/handler.lua",
    ["kong.plugins.graphql-proxy-cache-advanced.schema"] = "kong/plugins/graphql-proxy-cache-advanced/schema.lua",
    ["kong.plugins.graphql-proxy-cache-advanced.strategies"] = "kong/plugins/graphql-proxy-cache-advanced/strategies/init.lua",
    ["kong.plugins.graphql-proxy-cache-advanced.strategies.memory"] = "kong/plugins/graphql-proxy-cache-advanced/strategies/memory.lua",
    ["kong.plugins.graphql-proxy-cache-advanced.api"] = "kong/plugins/graphql-proxy-cache-advanced/api.lua",
    ["kong.plugins.graphql-proxy-cache-advanced.cache_key"] = "kong/plugins/graphql-proxy-cache-advanced/cache_key.lua",
  }
}
