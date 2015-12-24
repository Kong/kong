local validations = require "kong.dao.schemas_validation"
local crud = require "kong.api.crud_helpers"
local is_uuid = validations.is_valid_uuid

return {
  ["/consumers/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.consumers)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.consumers)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.consumers)
    end
  },

  ["/consumers/:username_or_id"] = {
    before = function(self, dao_factory)
      self.fetch_keys = {
        [is_uuid(self.params.username_or_id) and "id" or "username"] = self.params.username_or_id
      }
      self.params.username_or_id = nil
    end,

    GET = function(self, dao_factory)
      crud.get(self.fetch_keys, dao_factory.consumers)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.consumers, self.fetch_keys)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(nil, dao_factory.consumers, self.fetch_keys)
    end
  }
}
