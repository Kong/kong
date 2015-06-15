local crud = require "kong.api.crud_helpers"

return {
  ["/consumers/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.consumers)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.consumers)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.consumers)
    end
  },

  ["/consumers/:username_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end,

    PATCH = function(self, dao_factory, helpers)
      crud.patch(self.params, self.consumer, dao_factory.consumers)
    end,

    DELETE = function(self, dao_factory, helpers)
      crud.delete({id = self.consumer.id}, dao_factory.consumers)
    end
  }
}
