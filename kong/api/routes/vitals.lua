local endpoints = require "kong.api.endpoints"


local kong = kong


if not kong.configuration.vitals then
  return {}
end


local function fetch_consumer(self, helpers, db, consumer_id)
  if not consumer_id then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  self.args = {}
  self.params.consumers = ngx.unescape_uri(consumer_id)

  self.consumer = endpoints.select_entity(self, db, db.consumers.schema)
  if not self.consumer then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

return {
  ["/vitals/"] = {
    GET = function(self, dao, helpers)
      local data = kong.vitals:get_index()

      return helpers.responses.send_HTTP_OK(data)
    end
  },
  ["/vitals/cluster"] = {
    GET = function(self, dao, helpers)
      local cluster_stats, err = kong.vitals:get_stats(
          self.params.interval,
          "cluster",
          nil,
          self.params.start_ts)

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
        start_ts = self.params.start_ts,
        level = "cluster",
        entity_type = "cluster",
      }

      local status_codes, err = kong.vitals:get_status_codes(opts)

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
      local all_node_stats, err = kong.vitals:get_stats(
          self.params.interval,
          "node",
          nil,
          self.params.start_ts
      )

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
      local requested_node_stats, err = kong.vitals:get_stats(
          self.params.interval,
          "node",
          self.params.node_id,
          self.params.start_ts
      )

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
  ["/vitals/consumers/:consumer_id/cluster"] = {
    GET = function(self, _, helpers)
      -- XXX can't use second paremeter here - it's the old dao
      local db = kong.db
      fetch_consumer(self, helpers, db, self.params.consumer_id)

      local opts = {
        consumer_id = self.consumer.id,
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local cluster_stats, err = kong.vitals:get_consumer_stats(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          -- something went wrong in the arguments we set, not user-entered
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(cluster_stats)
    end
  },
  ["/vitals/status_codes/by_service"] = {
    GET = function(self, dao, helpers)
      local service, service_err = kong.db.services:select({ id = self.params.service_id })

      if service_err then
        helpers.responses.send_HTTP_BAD_REQUEST("Invalid query params: service_id is invalid")
      end

      if not service then
        helpers.responses.send_HTTP_NOT_FOUND()
      end

      local opts = {
        entity_type = "service",
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        entity_id   = self.params.service_id,
        level       = "cluster",
        workspace_id = ngx.ctx.workspaces[1] and ngx.ctx.workspaces[1].id,
      }

      local status_codes, err = kong.vitals:get_status_codes(opts)

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
      local route, route_err = kong.db.routes:select({ id = self.params.route_id })

      if route_err then
        helpers.responses.send_HTTP_BAD_REQUEST("Invalid query params: route_id is invalid")
      end

      if not route then
        helpers.responses.send_HTTP_NOT_FOUND()
      end

      local opts = {
        entity_type = "route",
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        entity_id   = self.params.route_id,
        level       = "cluster",
        workspace_id = ngx.ctx.workspaces[1] and ngx.ctx.workspaces[1].id,
      }

      local status_codes, err = kong.vitals:get_status_codes(opts)

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
  ["/vitals/status_codes/by_consumer"] = {
    GET = function(self, _, helpers)
      -- XXX can't use second paremeter here - it's the old dao
      local db = kong.db
      fetch_consumer(self, helpers, db, self.params.consumer_id)

      local opts = {
        entity_type = "consumer",
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        entity_id   = self.consumer.id,
        level       = "cluster",
      }

      local requested_routes, err = kong.vitals:get_status_codes(opts)
      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(requested_routes)
    end
  },
  ["/vitals/status_codes/by_consumer_and_route"] = {
    GET = function(self, dao, helpers)
      -- XXX can't use second paremeter here - it's the old dao
      local db = kong.db
      fetch_consumer(self, helpers, db, self.params.consumer_id)

      local opts = {
        entity_type = "consumer_route",
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        entity_id   = self.consumer.id,
        level       = "cluster",
        workspace_id = ngx.ctx.workspaces[1] and ngx.ctx.workspaces[1].id,
      }

      local requested_routes, err = kong.vitals:get_status_codes(opts, "route_id")

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(requested_routes)
    end
  },
  ["/vitals/status_code_classes"] = {
    GET = function(self, dao, helpers)
      -- assume request is not workspace-specific
      local entity_type = "cluster"
      local entity_id = nil

      -- if you explicitly passed a workspace, then we'll find those
      -- status_code_classes. Otherwise, we assume you meant cluster-level.
      if string.find(ngx.var.uri, "/vitals") > 1 then
        entity_type = "workspace"
        entity_id = ngx.ctx.workspaces[1] and ngx.ctx.workspaces[1].id
      end

      local opts = {
        entity_type = entity_type,
        entity_id   = entity_id,
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = kong.vitals:get_status_codes(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        else
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_OK(res)
    end
  },
}
