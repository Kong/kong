local BasePlugin = require "kong.plugins.base_plugin"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"

local CacheReadOnly = BasePlugin:extend()

CacheReadOnly.PRIORITY = 1000

function CacheReadOnly:new()
  CacheReadOnly.super.new(self, "cache-readonly")
end

local function update_table(t)
  t.msg = "new value"
end

function CacheReadOnly:access(conf)
  CacheReadOnly.super.access(self)

  cache.set("hello", {msg = "world"})

  local v = cache.get("hello")
  local res, err = pcall(update_table, v)
  if not res then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
end

return CacheReadOnly