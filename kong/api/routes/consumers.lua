local crud = require "kong.api.crud_helpers"
local Endpoints = require "kong.api.endpoints"


local escape_uri   = ngx.escape_uri


return {

  ["/consumers"] = {
    GET = function(self, dao_factory, helpers)
      local db = dao_factory.db.new_db

      if self.params.custom_id then
        local consumer, _, err_t = db.consumers:select_by_custom_id(self.params.custom_id)
        if err_t then
          return Endpoints.handle_error(err_t)
        end

        return helpers.responses.send_HTTP_OK {
          data   = { consumer },
        }
      end

      local data, _, err_t, offset = db.consumers:page(self.args.size,
                                                       self.args.offset,
                                                       { nulls = true })
      if err_t then
        return Endpoints.handle_error(err_t)
      end

      local next_page = offset and "/consumers?offset=" .. escape_uri(offset)
                                or ngx.null

      return helpers.responses.send_HTTP_OK {
        data   = data,
        offset = offset,
        next   = next_page,
      }
    end,
  },

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
