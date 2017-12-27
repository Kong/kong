local crud = require "kong.api.crud_helpers"

local function post_process_label_from_id(self, dao_factory, helpers, data)
  self.params.label_name_or_id = data.label_id
  crud.find_label_by_name_or_id(self, dao_factory, helpers)
  return self.label
end

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
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
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
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
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

  ["/consumers/:username_or_id/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
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


  ["/consumers/:username_or_id/labels/"] = {
    before = function(self, dao_factory, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.label_mappings, function(data)
        return post_process_label_from_id(self, dao_factory, helpers, data)
      end)
    end,

    POST = function(self, dao_factory, helpers)
      -- TODO check if label_id is present in the request
      crud.post(self.params, dao_factory.label_mappings, function(data)
        return post_process_label_from_id(self, dao_factory, helpers, data)
      end)
    end,
  },

  ["/consumers/:username_or_id/labels/:label_name_or_id"] = {
    before = function(self, dao_factory, helpers)
      -- lookup consumer
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)

      -- lookup label
      crud.find_label_by_name_or_id(self, dao_factory, helpers)


      -- return 404 if no mapping between label and api
      local rows, err = dao_factory.label_mappings:find_all {
        label_id = self.label.id,
        consumer_id = self.consumer.id,
      }
      if err then
        return helpers.yield_error(err)
      end

      self.label_mapping = rows[1]
      if not self.label_mapping then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- self.consumer, self.label, self.label_mapping populated
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.label)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.label_mapping, dao_factory.label_mappings)
    end
  },
}
