local utils = require "kong.tools.utils"
local declarative = require "kong.db.declarative"

local tonumber = tonumber
local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()


local dbless = kong.configuration.database == "off"
local data_plane_role = kong.configuration.role == "data_plane"

local get_worker_count  = ngx.worker.count
local constants         = require "kong.constants"
local kong_shm          = ngx.shared.kong
local DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY = constants.DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY
local DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY = constants.DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY

local declarative = require "kong.db.declarative"

local INIT_HASH = "00000000000000000000000000000000"
local get_cur_hash = declarative.get_current_hash;

local function is_ready()
  local ok, err = kong.db:connect()

  if not ok then
    return false
  end

  -- FIXME: should we use this condition?
  if dbless and data_plane_role then
    local router_rebuilds = 
                      kong_shm:get(DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY) or 0
    local plugins_iterator_rebuilds = 
                      kong_shm:get(DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY) or 0
    local num_worker = get_worker_count()

    if router_rebuilds <= num_worker 
        or plugins_iterator_rebuilds <= num_worker then
      return false
    end

    local current_hash = get_cur_hash()

    if not current_hash or current_hash == INIT_HASH then
      return false
    end
  end

  kong.db:close() -- ignore errors
  return true
end

return {
  ["/status/ready"] = {
    GET = function(self, dao, helpers)
      if is_ready() then
        return kong.response.exit(200, "OK")
      else
        return kong.response.exit(503, "")
      end
    end
  },
  ["/status"] = {
    GET = function(self, dao, helpers)
      local query = self.req.params_get
      local unit = "m"
      local scale

      if query then
        if query.unit then
          unit = query.unit
        end

        if query.scale then
          scale = tonumber(query.scale)
        end

        -- validate unit and scale arguments

        local pok, perr = pcall(utils.bytes_to_str, 0, unit, scale)
        if not pok then
          return kong.response.exit(400, { message = perr })
        end
      end

      -- nginx stats
      local status_response = {
        memory = knode.get_memory_stats(unit, scale),
        server = kong.nginx.get_statistics(),
        database = {
          reachable = true,
        },
      }

      -- if dbless mode is enabled we provide the current hash of the
      -- data-plane in the status response as this enables control planes
      -- to make decisions when something changes in the data-plane (e.g.
      -- if the gateway gets unexpectedly restarted and its configuration
      -- has been reset to empty).
      if dbless or data_plane_role then
        status_response.configuration_hash = declarative.get_current_hash()
      end

      -- TODO: no way to bypass connection pool
      local ok, err = kong.db:connect()
      if not ok then
        ngx.log(ngx.ERR, "failed to connect to ", kong.db.infos.strategy,
                         " during /status endpoint check: ", err)
        status_response.database.reachable = false
      end

      kong.db:close() -- ignore errors

      return kong.response.exit(200, status_response)
    end
  },
}
