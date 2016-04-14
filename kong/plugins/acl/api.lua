local crud = require "kong.api.crud_helpers"

return {
  ["/consumers/:username_or_id/acls/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.acls)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.acls)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.acls)
    end
  },

  ["/consumers/:username_or_id/acls/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local err
      self.acl, err = dao_factory.acls:find(self.params)
      if err then
        return helpers.yield_error(err)
      elseif self.acl == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.acl)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.acls, self.acl)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.acl, dao_factory.acls)
    end
  }
}
