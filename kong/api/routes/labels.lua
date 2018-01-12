local crud = require "kong.api.crud_helpers"

return {
  ["/labels/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.labels)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.labels)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.labels)
    end
  },

  ["/labels/:label_name_or_id/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_label_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.label)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.labels, self.label)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.label, dao_factory.labels)
    end
  },

  ["/labels/:label_name_or_id/plugins/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_label_by_name_or_id(self, dao_factory, helpers)
      self.params.label_id = self.label.id
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

  ["/labels/:label_name_or_id/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_label_by_name_or_id(self, dao_factory, helpers)
      crud.find_plugin_by_filter(self, dao_factory, {
        label_id = self.label.id,
        id     = self.params.id,
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
