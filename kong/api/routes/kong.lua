local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"

local find = string.find
local pairs = pairs
local ipairs = ipairs
local select = select
local tonumber = tonumber

local tagline = "Welcome to ".._KONG._NAME
local version = _KONG._VERSION
local lua_version = jit and jit.version or _VERSION

return {
  ["/"] = {
    GET = function(self, dao, helpers)
      local rows, err = dao.plugins:find_all()
      if err then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      local m = {}
      for _, row in ipairs(rows) do
        m[row.name] = true
      end

      local distinct_plugins = {}
      for plugin_name in pairs(m) do
        distinct_plugins[#distinct_plugins + 1] = plugin_name
      end

      return helpers.responses.send_HTTP_OK {
        tagline = tagline,
        version = version,
        hostname = utils.get_hostname(),
        timers = {
          running = ngx.timer.running_count(),
          pending = ngx.timer.pending_count()
        },
        plugins = {
          available_on_server = singletons.configuration.plugins,
          enabled_in_cluster = distinct_plugins
        },
        lua_version = lua_version,
        configuration = singletons.configuration
      }
    end
  },
  ["/status"] = {
    GET = function(self, dao, helpers)
      local r = ngx.location.capture "/nginx_status"
      if r.status ~= 200 then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(r.body)
      end

      local var = ngx.var
      local accepted, handled, total = select(3, find(r.body, "accepts handled requests\n (%d*) (%d*) (%d*)"))

      local status_response = {
        server = {
          connections_active = tonumber(var.connections_active),
          connections_reading = tonumber(var.connections_reading),
          connections_writing = tonumber(var.connections_writing),
          connections_waiting = tonumber(var.connections_waiting),
          connections_accepted = tonumber(accepted),
          connections_handled = tonumber(handled),
          total_requests = tonumber(total)
        },
        database = {}
      }

      for k, v in pairs(dao.daos) do
        local count, err = v:count()
        if err then
          return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end
        status_response.database[k] = count
      end

      return helpers.responses.send_HTTP_OK(status_response)
    end
  }
}
