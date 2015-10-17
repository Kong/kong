local constants = require "kong.constants"
local route_helpers = require "kong.api.route_helpers"
local utils = require "kong.tools.utils"

return {
  ["/"] = {
    GET = function(self, dao, helpers)
      local db_plugins, err = dao.plugins:find_distinct()
      if err then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      return helpers.responses.send_HTTP_OK({
        tagline = "Welcome to Kong",
        version = constants.VERSION,
        hostname = utils.get_hostname(),
        plugins = {
          available_on_server = configuration.plugins_available,
          enabled_in_cluster = db_plugins
        },
        lua_version = jit and jit.version or _VERSION
      })
    end
  },
  ["/status"] = {
    GET = function(self, dao, helpers)
      local res = ngx.location.capture("/nginx_status")
      if res.status == 200 then

        local status_response = {
          server = route_helpers.parse_status(res.body),
          database = {}
        }

        for k, v in pairs(dao.daos) do
          local count, err = v:count_by_keys()
          if err then
            return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
          end
          status_response.database[k] = count
        end

        return helpers.responses.send_HTTP_OK(status_response)
      else
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(res.body)
      end
    end
  }
}
