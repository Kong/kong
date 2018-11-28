local crud = require "kong.api.crud_helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local ee_crud    = require "kong.enterprise_edition.crud_helpers"

return {
  ["/consumers/"] = {
    before = function(self, dao_factory, helpers)
      -- prevent users from changing consumer type
      if self.params.type and tostring(self.params.type) ~= tostring(enums.CONSUMERS.TYPE.PROXY) then
        helpers.responses.send_HTTP_BAD_REQUEST("type is invalid")
      end
    end,

    GET = function(self, dao_factory)
      self.params.type = enums.CONSUMERS.TYPE.PROXY
      crud.paginated_set(self, dao_factory.consumers)
    end,

    PUT = function(self, dao_factory)
      self.params.type = enums.CONSUMERS.TYPE.PROXY
      crud.put(self.params, dao_factory.consumers)
    end,

    POST = function(self, dao_factory)
      self.params.type = enums.CONSUMERS.TYPE.PROXY
      crud.post(self.params, dao_factory.consumers)
    end
  },

  ["/consumers/:username_or_id"] = {
    before = function(self, dao_factory, helpers)
      self.params.type = enums.CONSUMERS.TYPE.PROXY
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      ee_crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.consumers, self.consumer)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.consumer, dao_factory.consumers)
    end
  },

  ["/consumers/:username_or_id/plugins/"] = {
    before = function(self, dao_factory, helpers)
      self.params.type = enums.CONSUMERS.TYPE.PROXY
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      ee_crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
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

  ["/consumers/:username_or_id/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      self.params.type = enums.CONSUMERS.TYPE.PROXY
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      ee_crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
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
