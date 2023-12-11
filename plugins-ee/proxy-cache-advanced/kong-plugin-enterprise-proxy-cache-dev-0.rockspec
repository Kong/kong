package = "kong-plugin-enterprise-proxy-cache"
version = "dev-0"

source = {
  url = "git://github.com/Kong/kong-plugin-enterprise-proxy-cache",
  tag = "dev"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "HTTP Proxy Caching for Kong Enterprise",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.proxy-cache-advanced.handler"]                             = "kong/plugins/proxy-cache-advanced/handler.lua",
    ["kong.plugins.proxy-cache-advanced.cache_key"]                           = "kong/plugins/proxy-cache-advanced/cache_key.lua",
    ["kong.plugins.proxy-cache-advanced.schema"]                              = "kong/plugins/proxy-cache-advanced/schema.lua",
    ["kong.plugins.proxy-cache-advanced.api"]                                 = "kong/plugins/proxy-cache-advanced/api.lua",
    ["kong.plugins.proxy-cache-advanced.strategies"]                          = "kong/plugins/proxy-cache-advanced/strategies/init.lua",
    ["kong.plugins.proxy-cache-advanced.strategies.memory"]                   = "kong/plugins/proxy-cache-advanced/strategies/memory.lua",
    ["kong.plugins.proxy-cache-advanced.strategies.redis"]                    = "kong/plugins/proxy-cache-advanced/strategies/redis.lua",
  }
}
