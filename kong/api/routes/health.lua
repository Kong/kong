local utils = require "kong.tools.utils"

local find = string.find
local select = select
local tonumber = tonumber
local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()


local select = select
local tonumber = tonumber
local kong = kong


return {
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

      local r = ngx.location.capture "/nginx_status"
      if r.status ~= 200 then
        kong.log.err(r.body)
        return kong.response.exit(500, { message = "An unexpected error happened" })
      end

      local var = ngx.var
      local accepted, handled, total = select(3, find(r.body, "accepts handled requests\n (%d*) (%d*) (%d*)"))

      local status_response = {
        memory = knode.get_memory_stats(unit, scale),
        server = {
          connections_active = tonumber(var.connections_active),
          connections_reading = tonumber(var.connections_reading),
          connections_writing = tonumber(var.connections_writing),
          connections_waiting = tonumber(var.connections_waiting),
          connections_accepted = tonumber(accepted),
          connections_handled = tonumber(handled),
          total_requests = tonumber(total)
        },
        database = {
          reachable = true,
        },
      }

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
