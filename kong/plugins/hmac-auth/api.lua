local crud = require "kong.api.crud_helpers"

return{
  ["/consumers/:username_or_id/hmac-auth/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.hmacauth_credentials)
    end,

    PUT = function(self, dao_factory)
     crud.put(self.params, dao_factory.hmacauth_credentials)
    end,

    POST = function(self, dao_factory)
     crud.post(self.params, dao_factory.hmacauth_credentials)
    end
  },

  ["/consumers/:username_or_id/hmac-auth/:credential_username_or_id"]  = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local credentials, err = crud.find_by_id_or_field(
        dao_factory.hmacauth_credentials,
        { consumer_id = self.params.consumer_id },
        self.params.credential_username_or_id,
        "username"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
      self.params.credential_username_or_id = nil

      self.hmacauth_credential = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.hmacauth_credential)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.hmacauth_credentials, self.hmacauth_credential)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.hmacauth_credential, dao_factory.hmacauth_credentials)
    end
  }
}
