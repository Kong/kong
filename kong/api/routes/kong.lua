local constants = require "kong.constants"

local function get_hostname()
  local f = io.popen ("/bin/hostname")
  local hostname = f:read("*a") or ""
  f:close()
  hostname = string.gsub(hostname, "\n$", "")
  return hostname
end

local METHOD_NOT_ALLOWED_MESSAGE = { message = "Method not allowed" }

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
        hostname = get_hostname(),
        plugins = {
          available_on_server = configuration.plugins_available,
          enabled_in_cluster = db_plugins
        },
        lua_version = jit and jit.version or _VERSION
      })
    end,
    POST = function(self, dao, helpers)
      return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED(METHOD_NOT_ALLOWED_MESSAGE)
    end,
    PUT = function(self, dao, helpers)
      return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED(METHOD_NOT_ALLOWED_MESSAGE)
    end,
    PATCH = function(self, dao, helpers)
      return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED(METHOD_NOT_ALLOWED_MESSAGE)
    end,
    DELETE = function(self, dao, helpers)
      return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED(METHOD_NOT_ALLOWED_MESSAGE)
    end
  }
}
