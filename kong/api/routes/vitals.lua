-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local endpoints = require "kong.api.endpoints"


local kong = kong


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

local function enabled_only()
  if not kong.configuration.vitals then
    return kong.response.exit(404, { message = "Not found" })
  end
end

return {
  ["/vitals/"] = {
    before = enabled_only,

    GET = function(self, dao, helpers)
      local data = kong.vitals:get_index()

      return kong.response.exit(200, data)
    end
  },
  ["/vitals/cluster"] = {
    before = enabled_only,

    GET = function(self, dao, helpers)
      local cluster_stats, err = kong.vitals:get_stats(
        self.params.interval,
        "cluster",
        nil,
        self.params.start_ts,
        self.params.end_ts
      )

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
    before = enabled_only,

    GET = function(self, dao, helpers)
      local opts = {
        duration = self.params.interval,
        start_ts = self.params.start_ts,
        end_ts = self.params.end_ts,
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
    before = enabled_only,

    GET = function(self, dao, helpers)
      local all_node_stats, err = kong.vitals:get_stats(
          self.params.interval,
          "node",
          nil,
          self.params.start_ts,
          self.params.end_ts
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
    before = enabled_only,

    GET = function(self, dao, helpers)
      local requested_node_stats, err = kong.vitals:get_stats(
          self.params.interval,
          "node",
          self.params.node_id,
          self.params.start_ts,
          self.params.end_ts
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
    before = enabled_only,

    GET = function(self, _, helpers)
      -- XXX can't use second paremeter here - it's the old dao
      local db = kong.db
      fetch_consumer(self, helpers, db, self.params.consumer_id)

      local opts = {
        consumer_id = self.consumer.id,
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        end_ts      = self.params.end_ts,
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
    before = enabled_only,

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
        end_ts      = self.params.end_ts,
        entity_id   = self.params.service_id,
        level       = "cluster",
        workspace_id = ngx.ctx.workspace,
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
    before = enabled_only,

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
        end_ts      = self.params.end_ts,
        entity_id   = self.params.route_id,
        level       = "cluster",
        workspace_id = ngx.ctx.workspace,
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
    before = enabled_only,

    GET = function(self, _, helpers)
      -- XXX can't use second paremeter here - it's the old dao
      local db = kong.db
      fetch_consumer(self, helpers, db, self.params.consumer_id)

      local opts = {
        entity_type = "consumer",
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        end_ts      = self.params.end_ts,
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
    before = enabled_only,

    GET = function(self, dao, helpers)
      -- XXX can't use second paremeter here - it's the old dao
      local db = kong.db
      fetch_consumer(self, helpers, db, self.params.consumer_id)

      local opts = {
        entity_type = "consumer_route",
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        end_ts      = self.params.end_ts,
        entity_id   = self.consumer.id,
        level       = "cluster",
        workspace_id = ngx.ctx.workspace,
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
    before = enabled_only,

    GET = function(self, dao, helpers)
      -- assume request is not workspace-specific
      local entity_type = "cluster"
      local entity_id = nil

      -- if you explicitly passed a workspace, then we'll find those
      -- status_code_classes. Otherwise, we assume you meant cluster-level.
      if string.find(ngx.var.uri, "/vitals") > 1 then
        entity_type = "workspace"
        entity_id = ngx.ctx.workspace
      end

      local opts = {
        entity_type = entity_type,
        entity_id   = entity_id,
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        end_ts      = self.params.end_ts,
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

  ["/vitals/reports/:entity_type"] = {
    before = enabled_only,

    GET = function(self, dao, helpers)
      kong.log.warn("DEPRECATED: Support for the /vitals/reports/:entity_type" ..
        " endpoint is deprecated, please use the Vitals API instead.")

      local opts = {
        entity_type = self.params.entity_type,
        entity_id   = self.params.entity_id,
        start_ts    = self.params.start_ts,
        interval    = self.params.interval,
      }
      local report, err = kong.vitals:get_report(opts)

      if err then
        if err:find("Invalid query params", nil, true) then
          return kong.response.exit(400, { message = err })

        else
          return helpers.yield_error(err)
        end
      end

      return kong.response.exit(200, report)
    end
  },
}

