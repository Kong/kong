local ffi = require("ffi")
local C = ffi.C
local utils = require "kong.tools.utils"
local declarative = require "kong.db.declarative"

local tonumber = tonumber
local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()


local dbless = kong.configuration.database == "off"
local data_plane_role = kong.configuration.role == "data_plane"


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

      if ffi.arch == "x64" or ffi.arch == "arm64" then
        ffi.cdef[[
        uint64_t *ngx_stat_requests;
        uint64_t *ngx_stat_accepted;
        uint64_t *ngx_stat_handled;
        uint64_t *ngx_stat_active;
        uint64_t *ngx_stat_reading;
        uint64_t *ngx_stat_writing;
        uint64_t *ngx_stat_waiting;
        ]]
      elseif ffi.arch == "x86" or ffi.arch == "arm" then
        ffi.cdef[[
        uint32_t *ngx_stat_requests;
        uint32_t *ngx_stat_accepted;
        uint32_t *ngx_stat_handled;
        uint32_t *ngx_stat_active;
        uint32_t *ngx_stat_reading;
        uint32_t *ngx_stat_writing;
        uint32_t *ngx_stat_waiting;
        ]]
      else
        kong.log.err("Unsupported arch: " .. ffi.arch)
      end

      local accepted = C.ngx_stat_accepted[0]
      local handled = C.ngx_stat_handled[0]
      local total = C.ngx_stat_requests[0]

      local var = ngx.var
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
