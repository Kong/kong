local singletons = require "kong.singletons"
local crud       = require "kong.api.crud_helpers"

if not singletons.configuration.vitals then
  return {}
end

return {
  ["/vitals/"] = {
    GET = function(self, dao, helpers)
      local data = singletons.vitals:get_index()

      return helpers.responses.send_HTTP_OK(data)
    end
  },
  ["/vitals/cluster"] = {
    GET = function(self, dao, helpers)
      local cluster_stats, err = singletons.vitals:get_stats(self.params.interval, "cluster", nil)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(cluster_stats)
    end
  },
  ["/vitals/nodes/"] = {
    GET = function(self, dao, helpers)
      local all_node_stats, err = singletons.vitals:get_stats(self.params.interval, "node", nil)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(all_node_stats)
    end
  },
  ["/vitals/nodes/:node_id"] = {
    GET = function(self, dao, helpers)
      local requested_node_stats, err = singletons.vitals:get_stats(self.params.interval, "node", self.params.node_id)

      if err then
        if err:find("Invalid query params: invalid node_id") or err:find("node does not exist") then
          return helpers.responses.send_HTTP_NOT_FOUND()
        elseif err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(requested_node_stats)
    end
  },
  ["/vitals/consumers/:username_or_id/cluster"] = {
    GET = function(self, dao, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao, helpers)

      local opts = {
        consumer_id = self.consumer.id,
        duration    = self.params.interval,
        level       = "cluster"
      }

      local cluster_stats, err = singletons.vitals:get_consumer_stats(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST("Invalid query params: interval must be 'minutes' or 'seconds'")

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(cluster_stats)
    end
  },
  ["/vitals/consumers/:username_or_id/nodes"] = {
    GET = function(self, dao, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao, helpers)

      local opts = {
        consumer_id = self.consumer.id,
        duration    = self.params.interval,
        level       = "node",
      }

      local requested_node_stats, err = singletons.vitals:get_consumer_stats(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST("Invalid query params: interval must be 'minutes' or 'seconds'")

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(requested_node_stats)
    end
  }
}
