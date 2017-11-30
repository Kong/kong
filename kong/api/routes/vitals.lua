local singletons = require "kong.singletons"

if not singletons.configuration.vitals then
  return {}
end

return {
  ["/vitals/"] = {
    resource = "vitals",

    GET = function(self, dao, helpers)
      local current_stats, _ = singletons.vitals:get_stats("seconds", "cluster", nil)

      return helpers.responses.send_HTTP_OK({ stats = current_stats })
    end
  },
  ["/vitals/cluster"] = {
    resource = "vitals",

    GET = function(self, dao, helpers)
      local cluster_stats, err = singletons.vitals:get_stats(self.params.interval, "cluster", nil)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK({ stats = cluster_stats })
    end
  },
  ["/vitals/nodes/"] = {
    resource = "vitals",

    GET = function(self, dao, helpers)
      local all_node_stats, err = singletons.vitals:get_stats(self.params.interval, "node", nil)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK({ stats = all_node_stats })
    end
  },
  ["/vitals/nodes/:node_id"] = {
    resource = "vitals",
    
    GET = function(self, dao, helpers)
      local requested_node_stats, err = singletons.vitals:get_stats(self.params.interval, "node", self.params.node_id)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK({ stats = requested_node_stats })
    end
  }
}
