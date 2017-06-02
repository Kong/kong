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

  ["/consumers/:username_or_id/acls/:group_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local acls, err = crud.find_by_id_or_field(
        dao_factory.acls,
        { consumer_id = self.params.consumer_id },
        self.params.group_or_id,
        "group"
      )

      if err then
        return helpers.yield_error(err)
      elseif #acls == 0 then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
      self.params.group_or_id = nil

      self.acl = acls[1]
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
