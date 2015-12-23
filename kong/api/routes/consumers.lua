local validations = require "kong.dao.schemas_validation"
local crud = require "kong.api.crud_helpers"

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
      if validations.is_valid_uuid(self.params.username_or_id) then
        self.params.id = self.params.username_or_id
      else
        self.params.username = self.params.username_or_id
      end
      self.params.username_or_id = nil
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.params, dao_factory.consumers)
    end,

    PATCH = function(self, dao_factory, helpers)
      crud.patch(self.params, dao_factory.consumers)
    end,

    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.params, dao_factory.consumers)
    end
  }
}
