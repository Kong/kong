local endpoints = require "kong.api.endpoints"


local kong = kong


if not kong.configuration.vitals then
  return {}
end


local function fetch_consumer(self, helpers, db, consumer_id)
  if not consumer_id then
    return kong.response.exit(404, { message = "Not found" })
  end

  self.args = {}
  self.params.consumers = ngx.unescape_uri(consumer_id)

  self.consumer = endpoints.select_entity(self, db, db.consumers.schema)
  if not self.consumer then
    return kong.response.exit(404, { message = "Not found" })
  end
end

return {
  ["/vitals/"] = {
    GET = function(self, dao, helpers)
      local data = kong.vitals:get_index()

      return kong.response.exit(200, data)
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
          return kong.response.exit(400, { message = err })

        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, cluster_stats)
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
          return kong.response.exit(400, { message = err })

        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, status_codes)
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
          return kong.response.exit(400, { message = err })

        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, all_node_stats)
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
          return kong.response.exit(404, { message = "Not found" })
        elseif err:find("Invalid query params", nil, true) then
          return kong.response.exit(400, { message = err })
        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, requested_node_stats)
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
          return kong.response.exit(400, { message = err })

        else
          -- something went wrong in the arguments we set, not user-entered
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, cluster_stats)
    end
  },
  ["/vitals/status_codes/by_service"] = {
    GET = function(self, dao, helpers)
      local service, service_err = kong.db.services:select({ id = self.params.service_id })

      if service_err then
        kong.response.exit(400, { message = "Invalid query params: service_id is invalid" })
      end

      if not service then
        kong.response.exit(404, { message = "Not found" })
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
          return kong.response.exit(400, { message = err })
        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, status_codes)
    end
  },
  ["/vitals/status_codes/by_route"] = {
    GET = function(self, dao, helpers)
      local route, route_err = kong.db.routes:select({ id = self.params.route_id })

      if route_err then
        kong.response.exit(400, { message = "Invalid query params: route_id is invalid" })
      end

      if not route then
        kong.response.exit(404, { message = "Not found" })
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
          return kong.response.exit(400, { message = err })
        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, status_codes)
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
          return kong.response.exit(400, { message = err })
        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, requested_routes)
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
          return kong.response.exit(400, { message = err })
        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, requested_routes)
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
          return kong.response.exit(400, { message = err })
        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, res)
    end
  },
}
