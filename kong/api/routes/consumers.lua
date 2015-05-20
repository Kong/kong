local validations = require("kong.dao.schemas")
local crud = require "kong.api.crud_helpers"

return {
  ["/consumers/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.consumers)
    end,

    PUT = function(self, dao_factory)
      crud.put(self, dao_factory.consumers)
    end,

    POST = function(self, dao_factory)
      crud.post(self, dao_factory.consumers)
    end
  },

  ["/consumers/:username_or_id"] = {
    before = function(self, dao_factory, helpers)
      local fetch_keys = {
        [validations.is_valid_uuid(self.params.username_or_id) and "id" or "username"] = self.params.username_or_id
      }
      self.params.username_or_id = nil

      local data, err = dao_factory.consumers:find_by_keys(fetch_keys)
      if err then
        return helpers.yield_error(err)
      end

      self.consumer = data[1]
      if not self.consumer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end,

    PATCH = function(self, dao_factory, helpers)
      self.params.id = self.consumer.id
      crud.patch(self.params, dao_factory.consumers)
    end,

    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.consumer.id, dao_factory.consumers)
    end
  }
}
