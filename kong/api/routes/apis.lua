local singletons = require "kong.singletons"
local crud = require "kong.api.crud_helpers"
local syslog = require "kong.tools.syslog"
local constants = require "kong.constants"
local validations = require "kong.dao.schemas_validation"
local is_uuid = validations.is_valid_uuid

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
    before = function(self, dao_factory)
      self.fetch_keys = {
        [is_uuid(self.params.name_or_id) and "id" or "name"] = self.params.name_or_id
      }
      self.params.name_or_id = nil
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.fetch_keys, dao_factory.apis)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.apis, self.fetch_keys)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(nil, dao_factory.apis, self.fetch_keys)
    end
  },

  ["/apis/:name_or_id/plugins/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.plugins, function(data)
        if singletons.configuration.send_anonymous_reports then
          data.signal = constants.SYSLOG.API
          syslog.log(syslog.format_entity(data))
        end
      end)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.plugins)
    end
  },

  ["/apis/:name_or_id/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
    end,

    GET = function(self, dao_factory)
      crud.get(self.params, dao_factory.plugins)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.plugins)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.params, dao_factory.plugins)
    end
  }
}
