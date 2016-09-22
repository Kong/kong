local crud = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"

return {
  ["/oauth2_tokens/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.oauth2_tokens)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.oauth2_tokens)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.oauth2_tokens)
    end
  },

  ["/oauth2_tokens/:token_or_id"] = {
    before = function(self, dao_factory, helpers)
      local filter_keys = {
        [utils.is_valid_uuid(self.params.token_or_id) and "id" or "access_token"] = self.params.token_or_id,
        consumer_id = self.params.consumer_id,
      }
      self.params.token_or_id = nil

      local credentials, err = dao_factory.oauth2_tokens:find_all(filter_keys)
      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.oauth2_token = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.oauth2_token)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.oauth2_tokens, self.oauth2_token)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.oauth2_token, dao_factory.oauth2_tokens)
    end
  },

  ["/oauth2/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.oauth2_credentials)
    end
  },

  ["/consumers/:username_or_id/oauth2/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.oauth2_credentials)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.oauth2_credentials)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.oauth2_credentials)
    end
  },

  ["/consumers/:username_or_id/oauth2/:clientid_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local filter_keys = {
        [utils.is_valid_uuid(self.params.clientid_or_id) and "id" or "client_id"] = self.params.clientid_or_id,
        consumer_id = self.params.consumer_id,
      }
      self.params.clientid_or_id = nil

      local credentials, err = dao_factory.oauth2_credentials:find_all(filter_keys)
      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.oauth2_credential = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.oauth2_credential)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.oauth2_credentials, self.oauth2_credential)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.oauth2_credential, dao_factory.oauth2_credentials)
    end
  }
}
