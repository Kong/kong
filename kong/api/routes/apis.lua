local crud = require "kong.api.crud_helpers"
local syslog = require "kong.tools.syslog"
local constants = require "kong.constants"

return {
  ["/apis/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.apis)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.apis)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.apis)
    end
  },

  ["/apis/:name_or_id"] = {
    before = crud.find_api_by_name_or_id,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.api)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, self.api, dao_factory.apis)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.api, dao_factory.apis)
    end
  },

  ["/apis/:name_or_id/plugins/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins_configurations)
    end,

    POST = function(self, dao_factory, helpers)
      crud.post(self.params, dao_factory.plugins_configurations, function(data)
        if configuration.send_anonymous_reports then
          data.signal = constants.SYSLOG.API
          syslog.log(syslog.format_entity(data))
        end
      end)
    end,

    PUT = function(self, dao_factory, helpers)
      crud.put(self.params, dao_factory.plugins_configurations)
    end
  },

  ["/apis/:name_or_id/plugins/:plugin_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id

      local fetch_keys = {
        api_id = self.api.id,
        id = self.params.plugin_id
      }
      self.params.plugin_id = nil

      local data, err = dao_factory.plugins_configurations:find_by_keys(fetch_keys)
      if err then
        return helpers.yield_error(err)
      end

      self.plugin = data[1]
      if not self.plugin then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.plugin)
    end,

    PATCH = function(self, dao_factory, helpers)
      crud.patch(self.params, self.plugin, dao_factory.plugins_configurations)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.plugin, dao_factory.plugins_configurations)
    end
  }
}
