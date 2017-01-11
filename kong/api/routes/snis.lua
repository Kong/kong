local crud = require "kong.api.crud_helpers"


return {
  ["/snis/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.ssl_servers_names)
    end,


    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.ssl_servers_names)
    end,


    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.ssl_servers_names)
    end,
  },


  ["/snis/:name"] = {
    before = function(self, dao_factory, helpers)
      local row, err = dao_factory.ssl_servers_names:find {
        name = self.params.name
      }
      if err then
        return helpers.yield_error(err)
      end

      if not row then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.sni = row
    end,


    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.sni)
    end,


    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.ssl_servers_names, self.sni)
    end,


    DELETE = function(self, dao_factory)
      crud.delete(self.sni, dao_factory.ssl_servers_names)
    end,
  }
}
