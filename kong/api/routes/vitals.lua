local endpoints = require "kong.api.endpoints"
local http  = require "resty.http"
local cjson = require "cjson"
local inspect = require "inspect"


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

local function influx_query(query)
  local address = kong.configuration.vitals_tsdb_address
  local user = kong.configuration.vitals_tsdb_user
  local password = kong.configuration.vitals_tsdb_password
  if address:sub(1, #"http") ~= "http" then
    address = "http://" .. address
  end
  local httpc = http.new()
  local data = { address = address, db = "kong", query = ngx.escape_uri(query) }
  local url = string.gsub("$address/query?db=$db&epoch=s&q=$query", "%$(%w+)", data)
  local headers = {}

  if user ~= nil and password ~= nil then
    headers = { ["Authorization"] = "Basic " .. ngx.encode_base64(user .. ":" .. password)}
  end

  local res, err = httpc:request_uri(url, { headers = headers})
  if not res then
    error(err)
  end

  if res.status ~= 200 then
    error(res.body)
  end

  local qres = cjson.decode(res.body)

  if #qres.results == 1 and qres.results[1].series then
    return qres.results[1].series
  elseif #qres.results > 1 then
    return qres.results
  else
    return {}
  end
end

local function status_code_report_by(entity, start_ts)
  start_ts = start_ts or 36000
  local query = "SELECT count(status) FROM kong.autogen.kong_request" ..
    " WHERE time > now() - " .. ngx.time() - start_ts .. "s" ..
    " GROUP BY " .. entity .. ", status_f"

  local result = influx_query(query)
  local stats = {}
  for i, row in pairs(result) do
    local lookup = {
      consumer = row.tags.consumer,
      service = row.tags.service
    }
    if stats[lookup[entity]] == nil then
      stats[lookup[entity]] = {}
    end

    local status_group = tostring(row.tags.status_f):sub(1, 1) .. "XX"
    local current_total = stats[lookup[entity]]["total"] or 0
    local current_status = stats[lookup[entity]][status_group] or 0

    stats[lookup[entity]]["total"] = current_total + row.values[1][2]
    stats[lookup[entity]][status_group] = current_status + row.values[1][2]
  end

  local meta = {
    earliest_ts = start_ts,
    latest_ts = ngx.time(),
    stat_labels = {
      "total",
      "2XX",
      "4XX",
      "5XX"
    },
  }

  return { stats=stats, meta=meta }
end

local function latency_report(start_ts)
  start_ts = start_ts or 36000
  local columns = {
    "proxy_max",
    "proxy_min",
    "proxy_avg",
    "upstream_max",
    "upstream_min",
    "upstream_avg",
  }
  local query = "SELECT MAX(proxy_latency), MIN(proxy_latency)," ..
    " MEAN(proxy_latency), MAX(request_latency), MIN(request_latency)," ..
    " MEAN(request_latency) FROM kong_request" ..
    " WHERE time > now() - " .. ngx.time() - start_ts .. "s" ..
    " GROUP BY hostname"

  local result = influx_query(query)

  local stats = {}
  for _, row in pairs(result) do
    local hostname = row.tags.hostname
    if stats[hostname] == nil then
      stats[hostname] = {}
    end
    for i, column in pairs(columns) do
      stats[hostname][column] = row.values[1][i+1]
    end
  end

  local meta = {
    earliest_ts = start_ts,
    latest_ts = ngx.time(),
    stat_labels = columns,
  }
  
  return { stats=stats, meta=meta }
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

  ["/vitals/reports/consumer"] = {
    GET = function(self, dao, helpers)
      return kong.response.exit(200, status_code_report_by("consumer", self.params.start_ts))
    end
  },

  ["/vitals/reports/service"] = {
    GET = function(self, dao, helpers)
      return kong.response.exit(200, status_code_report_by("service", self.params.start_ts))
    end
  },

  ["/vitals/reports/node"] = {
    GET = function(self, dao, helpers)
      return kong.response.exit(200, latency_report(self.params.start_ts))
    end
  },
}
