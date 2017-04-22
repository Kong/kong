local crud = require "kong.api.crud_helpers"

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

      local credentials, err = crud.find_by_id_or_field(
        dao_factory.jwt_secrets,
        { consumer_id = self.params.consumer_id },
        self.params.credential_key_or_id,
        "key"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
      self.params.credential_key_or_id = nil

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
