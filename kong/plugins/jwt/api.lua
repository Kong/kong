local crud = require "kong.api.crud_helpers"

return {
  ["/consumers/:username_or_id/jwt/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.jwt_secrets)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.jwt_secrets)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.jwt_secrets)
    end
  },

  ["/consumers/:username_or_id/jwt/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local data, err = dao_factory.jwt_secrets:find_by_keys({id = self.params.id})
      if err then
        return helpers.yield_error(err)
      end

      self.credential = data[1]
      if not self.credential then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.credential)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, self.credential, dao_factory.jwt_secrets)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.credential, dao_factory.jwt_secrets)
    end
  }
}
