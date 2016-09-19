local crud = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"

return {
  ["/consumers/:username_or_id/key-auth/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.keyauth_credentials)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.keyauth_credentials)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.keyauth_credentials)
    end
  },
  ["/consumers/:username_or_id/key-auth/:credential_key_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local filter_keys = {
        [utils.is_valid_uuid(self.params.credential_key_or_id) and "id" or "key"] = self.params.credential_key_or_id,
        consumer_id = self.params.consumer_id,
      }
      self.params.credential_key_or_id = nil

      local credentials, err = dao_factory.keyauth_credentials:find_all(filter_keys)
      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.keyauth_credential = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.keyauth_credential)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.keyauth_credentials, self.keyauth_credential)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.keyauth_credential, dao_factory.keyauth_credentials)
    end
  }
}
