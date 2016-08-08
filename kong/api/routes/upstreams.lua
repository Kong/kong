local crud = require "kong.api.crud_helpers"

return {
  ["/upstreams/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.upstreams)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.upstreams)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.upstreams)
    end
  },

  ["/upstreams/:name_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_upstream_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.upstream)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.upstreams, self.upstream)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.upstream, dao_factory.upstreams)
    end
  },

  ["/upstreams/:name_or_id/targets/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_upstream_by_name_or_id(self, dao_factory, helpers)
      self.params.upstream_id = self.upstream.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.targets)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.targets, function(data)
--todo: what is this? how does it work???
        data.signal = reports.upstream_signal
        reports.send(data)
      end)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.targets)
    end,

--todo: add a delete method, to delete a target without knowing an ID, just by hostname+port combo
  },

  ["/upstreams/:name_or_id/targets/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_upstream_by_name_or_id(self, dao_factory, helpers)
      local rows, err = dao_factory.targets:find_all {
        id = self.params.id,
        upstream_id = self.upstream.id
      }
      if err then
        return helpers.yield_error(err)
      elseif #rows == 0 then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.target = rows[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.target)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.targets, self.target)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.target, dao_factory.targets)
    end
  }
}
