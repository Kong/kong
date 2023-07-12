local declarative = require "kong.db.declarative"
local constants = require "kong.constants"

local ngx = ngx
local ngx_log = ngx.log
local ngx_NOTICE = ngx.NOTICE
local ngx_DEBUG = ngx.DEBUG

local tonumber = tonumber
local kong = kong
local fmt = string.format

local get_current_hash = declarative.get_current_hash


local worker_count = ngx.worker.count()
local kong_shm     = ngx.shared.kong

local is_dbless = kong.configuration.database == "off"
local is_control_plane = kong.configuration.role == "control_plane"

local PLUGINS_REBUILD_COUNTER_KEY = constants.PLUGINS_REBUILD_COUNTER_KEY
local ROUTERS_REBUILD_COUNTER_KEY = constants.ROUTERS_REBUILD_COUNTER_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local function is_dbless_ready(router_rebuilds, plugins_iterator_rebuilds)
  if router_rebuilds < worker_count then
    return false, fmt("router builds not yet complete, router ready"
      .. " in %d of %d workers", router_rebuilds, worker_count)
  end

  if plugins_iterator_rebuilds < worker_count then
    return false, fmt("plugins iterator builds not yet complete, "
      .. "plugins iterator ready in %d of %d workers",
      plugins_iterator_rebuilds, worker_count)
  end

  local current_hash = get_current_hash()

  if not current_hash then
    return false, "no configuration available (configuration hash is not initialized)"
  end

  if current_hash == DECLARATIVE_EMPTY_CONFIG_HASH then
    return false, "no configuration available (empty configuration present)"
  end

  return true
end


local function is_traditional_ready(router_rebuilds, plugins_iterator_rebuilds)
    -- traditional mode builds router from database once inside `init` phase
    if router_rebuilds == 0 then
      return false, "router builds not yet complete"
    end

    if plugins_iterator_rebuilds == 0 then
      return false, "plugins iterator build not yet complete"
    end

    return true
end

--[[
Checks if Kong is ready to serve.

@return boolean indicating if Kong is ready to serve.
@return string|nil an error message if Kong is not ready, or nil otherwise.
--]]
local function is_ready()
  local ok = kong.db:connect() -- for dbless, always ok

  if not ok then
    return false, "failed to connect to database"
  end
  
  kong.db:close()

  if is_control_plane then
    return true
  end

  local router_rebuilds = 
      tonumber(kong_shm:get(ROUTERS_REBUILD_COUNTER_KEY)) or 0
  local plugins_iterator_rebuilds = 
      tonumber(kong_shm:get(PLUGINS_REBUILD_COUNTER_KEY)) or 0

  local err
  -- full check for dbless mode
  if is_dbless then
    ok, err = is_dbless_ready(router_rebuilds, plugins_iterator_rebuilds)

  else
    ok, err = is_traditional_ready(router_rebuilds, plugins_iterator_rebuilds)
  end

  return ok, err
end

return {
  ["/status/ready"] = {
    GET = function(self, dao, helpers)
      local ok, err = is_ready()
      if ok then
        ngx_log(ngx_DEBUG, "ready for proxying")
        return kong.response.exit(200, { message = "ready" })

      else
        ngx_log(ngx_NOTICE, "not ready for proxying: ", err)
        return kong.response.exit(503, { message = err })
      end
    end
  }
}
