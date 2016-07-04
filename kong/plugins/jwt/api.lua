local crud = require "kong.api.crud_helpers"
local crypto = require "crypto"

return {
  ["/consumers/:username_or_id/jwt/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.jwt_secrets)
    end,

    PUT = function(self, dao_factory)
      if self.params.algorithm == "RS256" and self.params.rsa_public_key == nil then
          return helpers.responses.send_HTTP_BAD_REQUEST("No mandatory 'rsa_public_key'")
       end

      if self.params.algorithm == "RS256" and crypto.pkey.from_pem(self.params.rsa_public_key) == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST("'rsa_public_key' format is invalid")
      end

      if self.params.algorithm == "HS256" and self.params.secret == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST("No mandatory 'secret'")
      end

      crud.put(self.params, dao_factory.jwt_secrets)
    end,

    POST = function(self, dao_factory, helpers)
      if self.params.algorithm == "RS256" and self.params.rsa_public_key == nil then
          return helpers.responses.send_HTTP_BAD_REQUEST("No mandatory 'rsa_public_key'")
       end

      if self.params.algorithm == "RS256" and crypto.pkey.from_pem(self.params.rsa_public_key) == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST("'rsa_public_key' format is invalid")
      end

      if self.params.algorithm == "HS256" and self.params.secret == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST("No mandatory 'secret'")
      end

      crud.post(self.params, dao_factory.jwt_secrets)
    end
  },

  ["/consumers/:username_or_id/jwt/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local err
      self.jwt_secret, err = dao_factory.jwt_secrets:find(self.params)
      if err then
        return helpers.yield_error(err)
      elseif self.jwt_secret == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
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
