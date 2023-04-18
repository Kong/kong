local declarative = require "kong.db.declarative"
local constants = require "kong.constants"

local tonumber = tonumber
local kong = kong

local get_current_hash = declarative.get_current_hash


local worker_count = ngx.worker.count()
local kong_shm     = ngx.shared.kong

local ngx_log        = ngx.log
local ngx_WARN       = ngx.WARN

local is_traditional = kong.configuration.database ~= "off"

local DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY = 
                                constants.DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY
local DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY =
                                constants.DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH

--[[
Checks if Kong is ready to serve.

@return boolean indicating if Kong is ready to serve.
@return string|nil an error message if Kong is not ready, or nil otherwise.
--]]
local function is_ready()

  local ok = kong.db:connect()
  if not ok then
    return false, "failed to connect to database"
  end

  local router_rebuilds = 
      tonumber(kong_shm:get(DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY)) or 0
  local plugins_iterator_rebuilds = 
      tonumber(kong_shm:get(DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY)) or 0

  if (is_traditional and router_rebuilds == 0) 
      or router_rebuilds < worker_count then
    return false, "router rebuilds are not complete"
  end

  if (is_traditional and plugins_iterator_rebuilds == 0) 
      or plugins_iterator_rebuilds < worker_count then
    return false, "plugins iterator rebuilds are not complete"
  end

  if is_traditional then
    kong.db:close() -- ignore ERRs
    return true
  end

  local current_hash = get_current_hash()

  if not current_hash then
    return false, "no configuration hash"
  end

  if current_hash == DECLARATIVE_EMPTY_CONFIG_HASH then
    return false, "empty configuration hash"
  end

  kong.db:close()
  return true
end

return {
  ["/status/ready"] = {
    GET = function(self, dao, helpers)
      local ok, err = is_ready()
      if ok then
        return kong.response.exit(200, { message = "ready" })
      else
        ngx_log(ngx_WARN, "not ready: ", err)
        return kong.response.exit(503, { message = "not ready" })
      end
    end
  }
}
