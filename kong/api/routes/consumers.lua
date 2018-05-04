local crud = require "kong.api.crud_helpers"

return {

  ["/consumers/:consumers/plugins"] = {
    before = function(self, dao_factory, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.consumers)
      self.params.consumers = nil
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.plugins)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.plugins)
    end
  },

  ["/consumers/:consumers/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.consumers)
      self.params.consumers = nil
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      crud.find_plugin_by_filter(self, dao_factory, {
        consumer_id = self.consumer.id,
        id          = self.params.id,
      }, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.plugin)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.plugins, self.plugin)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.plugin, dao_factory.plugins)
    end
  },
}
