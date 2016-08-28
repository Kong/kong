local BasePlugin = require "kong.plugins.base_plugin"
local cache = require "kong.tools.database_cache"

local INVOCATIONS = "invocations"
local LOOKUPS = "lookups"

local DatabaseCacheHandler = BasePlugin:extend()

DatabaseCacheHandler.PRIORITY = 1000

function DatabaseCacheHandler:new()
  DatabaseCacheHandler.super.new(self, "database-cache")
end

function DatabaseCacheHandler:init_worker()
  DatabaseCacheHandler.super.init_worker(self)

  cache.rawset(INVOCATIONS, 0)
  cache.rawset(LOOKUPS, 0)
end

function DatabaseCacheHandler:access(conf)
  DatabaseCacheHandler.super.access(self)

  cache.get_or_set("pile_effect", function()
    cache.incr(LOOKUPS, 1)
    -- Adds some delay
    ngx.sleep(tonumber(ngx.req.get_uri_args().sleep))
    return true
  end)

  cache.incr(INVOCATIONS, 1)
end

return DatabaseCacheHandler
