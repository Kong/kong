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
  ["/vitals/cluster/status_codes"] = {
    GET = function(self, dao, helpers)
      local opts = {
        duration = self.params.interval,
        level    = "cluster"
      }

      local status_codes, err = singletons.vitals:get_status_code_classes(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(status_codes)
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
  },
  ["/vitals/services/:service_id/status_codes"] = {
    GET = function(self, dao, helpers)
      local service, service_err = singletons.db.services:select({ id = self.params.service_id })

      if service_err then
        helpers.responses.send_HTTP_BAD_REQUEST("Invalid query params: service_id is invalid")
      end

      if not service then
        helpers.responses.send_HTTP_NOT_FOUND()
      end

      local opts = {
        entity_type = "service",
        duration    = self.params.interval,
        service_id  = self.params.service_id,
        level       = "cluster",
      }

      local status_codes, err = singletons.vitals:get_status_codes(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(status_codes)
    end
  },
  ["/vitals/status_codes/by_route"] = {
    GET = function(self, dao, helpers)
      local route, route_err = singletons.db.routes:select({ id = self.params.route_id })

      if route_err then
        helpers.responses.send_HTTP_BAD_REQUEST("Invalid query params: route_id is invalid")
      end

      if not route then
        helpers.responses.send_HTTP_NOT_FOUND()
      end

      local opts = {
        entity_type = "route",
        duration    = self.params.interval,
        route_id    = self.params.route_id,
        level       = "cluster",
      }

      local status_codes, err = singletons.vitals:get_status_codes(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(status_codes)
    end
  },
}
