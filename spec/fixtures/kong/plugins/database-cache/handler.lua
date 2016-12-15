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

  cache.sh_set(INVOCATIONS, 0)
  cache.sh_set(LOOKUPS, 0)
end

local cb = function()
  cache.sh_incr(LOOKUPS, 1)
  -- Adds some delay
  ngx.sleep(tonumber(ngx.req.get_uri_args().sleep))
  return true
end

function DatabaseCacheHandler:access(conf)
  DatabaseCacheHandler.super.access(self)

  cache.get_or_set("pile_effect", nil, cb)

  cache.sh_incr(INVOCATIONS, 1)
end

return DatabaseCacheHandler