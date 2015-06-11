local crud = require "kong.api.crud_helpers"
local syslog = require "kong.tools.syslog"
local constants = require "kong.constants"

return {
  ["/plugins_configurations"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins_configurations)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.plugins_configurations)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.plugins_configurations, function(data)
        if configuration.send_anonymous_reports then
          data.signal = constants.SYSLOG.API
          syslog.log(syslog.format_entity(data))
        end
      end)
    end
  },

  ["/plugins_configurations/:id"] = {
    before = function(self, dao_factory, helpers)
      local err
      self.plugin_conf, err = dao_factory.plugins_configurations:find_one({ id = self.params.id })
      if err then
        return helpers.yield_error(err)
      elseif not self.plugin_conf then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.plugin_conf)
    end,

    PATCH = function(self, dao_factory)
      self.params.id = self.plugin_conf.id
      crud.patch(self.params, dao_factory.plugins_configurations)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.plugin_conf.id, dao_factory.plugins_configurations)
    end
  }
}
