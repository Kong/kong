local crud = require "kong.api.crud_helpers"

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

  ["/oauth2_tokens/:id"] = {
    GET = function(self, dao_factory)
      crud.get(self.params, dao_factory.oauth2_tokens)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.oauth2_tokens, self.params)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.oauth2_tokens)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.params, dao_factory.oauth2_tokens)
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

  ["/consumers/:username_or_id/oauth2/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local credentials, err = dao_factory.oauth2_credentials:find_all {
        consumer_id = self.params.consumer_id,
        id = self.params.id
      }
      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.oauth2_credential = credentials[1]
    end,

    GET = function(self, dao_factory)
      crud.get(self.params, dao_factory.oauth2_credentials)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.oauth2_credentials, self.params)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.params, dao_factory.oauth2_credentials)
    end
  }
}
