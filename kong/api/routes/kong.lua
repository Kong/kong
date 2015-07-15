local constants = require "kong.constants"
local route_helpers = require "kong.api.route_helpers"

return {
  ["/"] = {
    GET = function(self, dao, helpers)
      local db_plugins, err = dao.plugins_configurations:find_distinct()
      if err then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      return helpers.responses.send_HTTP_OK({
        tagline = "Welcome to Kong",
        version = constants.VERSION,
        hostname = route_helpers.get_hostname(),
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
        return helpers.responses.send_HTTP_OK(route_helpers.parse_status(res.body))
      else
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(res.body)
      end
    end
  }
}
