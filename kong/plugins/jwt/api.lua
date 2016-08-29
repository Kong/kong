local crud = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"

return {
  ["/consumers/:username_or_id/jwt/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.jwt_secrets)
    end,

    PUT = function(self, dao_factory, helpers)
      crud.put(self.params, dao_factory.jwt_secrets)
    end,

    POST = function(self, dao_factory, helpers)
      crud.post(self.params, dao_factory.jwt_secrets)
    end
  },

  ["/consumers/:username_or_id/jwt/:credential_key_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local filter_keys = {
        [utils.is_valid_uuid(self.params.credential_key_or_id) and "id" or "key"] = self.params.credential_key_or_id,
        consumer_id = self.params.consumer_id,
      }
      self.params.credential_key_or_id = nil

      local credentials, err = dao_factory.jwt_secrets:find_all(filter_keys)
      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.jwt_secret = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.jwt_secret)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.jwt_secrets, self.jwt_secret)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.jwt_secret, dao_factory.jwt_secrets)
    end
  }
}
