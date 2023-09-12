-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Copyright (C) Kong Inc.

local GqlSchema    = require "kong.gql.schema"
local build_ast    = require "kong.gql.query.build_ast"
local ratelimiting = require "kong.tools.public.rate-limiting"
local schema       = require "kong.plugins.graphql-rate-limiting-advanced.schema"
local cost         = require "kong.plugins.graphql-rate-limiting-advanced.cost"
local meta         = require "kong.meta"
local http         = require "resty.http"
local cjson        = require "cjson.safe"
local kong_global  = require "kong.global"
local utils        = require "kong.tools.utils"
local balancer     = require "kong.runloop.balancer"

local get_updated_now_ms = utils.get_updated_now_ms
local time_ns = utils.time_ns

local PHASES       = kong_global.phases


local ngx      = ngx
local kong     = kong
local max      = math.max
local tonumber = tonumber
local concat       = table.concat

local NewRLHandler = {
  PRIORITY = 902,
  VERSION = meta.core_version
}


local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"


local human_window_size_lookup = {
  [1]        = "second",
  [60]       = "minute",
  [3600]     = "hour",
  [86400]    = "day",
  [2592000]  = "month",
  [31536000] = "year",
}


local id_lookup = {
  ip = function()
    return ngx.var.remote_addr
  end,
  credential = function()
    return ngx.ctx.authenticated_credential and
           ngx.ctx.authenticated_credential.id
  end,
  consumer = function()
    -- try the consumer, fall back to credential
    return ngx.ctx.authenticated_consumer and
           ngx.ctx.authenticated_consumer.id or
           ngx.ctx.authenticated_credential and
           ngx.ctx.authenticated_credential.id
  end
}


local function new_namespace(config, init_timer)
  local ret = true

  kong.log.debug("attempting to add namespace ", config.namespace)

  local ok, err = pcall(function()
    local strategy = config.strategy == "cluster" and
                     kong.configuration.database or
                     "redis"

    if config.strategy == "cluster" and config.sync_rate ~= -1 then
      if kong.configuration.database == "off" or kong.configuration.role ~= "traditional" then
        ret = false

        local phase = ngx.get_phase()
        if phase == "init" or phase == "init_worker" then
          return nil, concat{ "[graphql-rate-limiting-advanced] strategy 'cluster' cannot ",
                              "be configured with DB-less mode or Hybrid mode. ",
                              "If you did not specify the strategy, please use the 'redis' strategy, ",
                              "or set 'sync_rate' to -1.", }
        end

        return kong.response.exit(500)
      end
    end

    local strategy_opts = strategy == "redis" and config.redis

    -- no shm was specified, try the default value specified in the schema
    local dict_name = config.dictionary_name
    if dict_name == nil then
      dict_name = schema.fields.dictionary_name.default
      kong.log.warn("no shared dictionary was specified.",
        " Trying the default value '", dict_name, "'...")
    end

    -- if dictionary name was passed but doesn't exist, fallback to kong
    if ngx.shared[dict_name] == nil then
      kong.log.notice("specified shared dictionary '", dict_name,
        "' doesn't exist. Falling back to the 'kong' shared dictionary")
      dict_name = "kong"
    end

    kong.log.notice("using shared dictionary '" .. dict_name .. "'")

    ratelimiting.new({
      namespace     = config.namespace,
      sync_rate     = config.sync_rate,
      strategy      = strategy,
      strategy_opts = strategy_opts,
      dict          = dict_name,
      window_sizes  = config.window_size,
      db            = kong.db,
    })
  end)

  -- if we created a new namespace, start the recurring sync timer and
  -- run an intial sync to fetch our counter values from the data store
  -- (if applicable)
  if ok then
    if init_timer and config.sync_rate > 0 then
      local rate = config.sync_rate
      local when = rate - (ngx.now() - (math.floor(ngx.now() / rate) * rate))
      kong.log.debug("initial sync in ", when, " seconds")
      ngx.timer.at(when, ratelimiting.sync, config.namespace)

      -- run the fetch from a timer because it uses cosockets
      -- kong patches this for psql and c*, but not redis
      ngx.timer.at(0, ratelimiting.fetch, config.namespace, ngx.now())
    end

  else
    kong.log.err("err in creating new ratelimit namespace: ", err)
    ret = false
  end

  return ret
end


function NewRLHandler:init_worker()
  self.gql_schema = {}
  self.costs = {}

  local worker_events = kong.worker_events

  -- event handlers to update recurring sync timers

  -- catch any plugins update and forward config data to each worker
  worker_events.register(function(data)
    if data.entity.name == "graphql-rate-limiting-advanced" then
      worker_events.post("gql-rl", data.operation, data.entity.config)
    end
  end, "crud", "plugins")

  -- new plugin? try to make a namespace!
  worker_events.register(function(config)
    if not ratelimiting.config[config.namespace] then
      new_namespace(config, true)
    end
  end, "gql-rl", "create")

  -- updates should clear the existing config and create a new
  -- namespace config. we do not initiate a new fetch/sync recurring
  -- timer as it's already running in the background
  worker_events.register(function(config)
    kong.log.debug("clear and reset ", config.namespace)

    -- if the previous config did not have a background timer,
    -- we need to start one
    local start_timer = false
    if ratelimiting.config[config.namespace].sync_rate <= 0 and
       config.sync_rate > 0 then

      start_timer = true
    end

    ratelimiting.clear_config(config.namespace)
    new_namespace(config, start_timer)

    -- clear the timer if we dont need it
    if config.sync_rate <= 0 then
      if ratelimiting.config[config.namespace] then
        ratelimiting.config[config.namespace].kill = true

      else
        kong.log.warn("did not find namespace ", config.namespace, " to kill")
      end
    end
  end, "gql-rl", "update")

  -- nuke this from orbit
  worker_events.register(function(config)
    -- set the kill flag on this namespace
    -- this will clear the config at the next sync() execution, and
    -- abort the recurring syncs
    if ratelimiting.config[config.namespace] then
      ratelimiting.config[config.namespace].kill = true

    else
      kong.log.warn("did not find namespace ", config.namespace, " to kill")
    end
  end, "gql-rl", "delete")
end

---
-- Execute the balancer and select an IP/port for the upstream.
--
-- This is mostly copy/paste from `Kong.balancer()`
--
---@param ctx table
---@param opts resty.websocket.client.connect.opts
---@param upstream_scheme "http"|"https"
local function get_peer(ctx, opts, upstream_scheme)
  local now_ms = get_updated_now_ms()

  if not ctx.KONG_BALANCER_START then
    ctx.KONG_BALANCER_START = now_ms
  end

  local balancer_data = ctx.balancer_data
  local tries = balancer_data.tries

  local old_phase = ctx.KONG_PHASE
  ctx.KONG_PHASE = PHASES.balancer
  local ok, err, errcode = balancer.execute(balancer_data, ctx, true)
  ctx.KONG_PHASE = old_phase
  if not ok then
    ngx.log(ngx.ERR, "failed to retry the dns/balancer resolver for ",
            tostring(balancer_data.host), "' with: ", tostring(err))

    return kong.response.exit(errcode)
  end

  local current_try = {}
  balancer_data.try_count = balancer_data.try_count + 1
  tries[balancer_data.try_count] = current_try

  current_try.balancer_start = now_ms
  current_try.balancer_start_ns = time_ns()

  if not balancer_data.preserve_host then
    -- set the upstream host header if not `preserve_host`
    local new_upstream_host = balancer_data.hostname
    local port = balancer_data.port

    if (port ~= 80  and port ~= 443)
    or (port == 80 and upstream_scheme ~= "http")
    or (port == 443 and upstream_scheme ~= "https")
    then
      new_upstream_host = new_upstream_host .. ":" .. port
    end

    if new_upstream_host ~= opts.host then
      opts.host = new_upstream_host
    end
  end

  if upstream_scheme == "https" then
    local server_name = opts.host

    -- the host header may contain a port number that needs to be stripped
    local pos = server_name:find(":")
    if pos then
      server_name = server_name:sub(1, pos - 1)
    end

    opts.server_name = server_name
  end

  current_try.ip   = balancer_data.ip
  current_try.port = balancer_data.port

  -- set the targets as resolved
  ngx.log(ngx.DEBUG, "setting address (try ", balancer_data.try_count, "): ",
                     balancer_data.ip, ":", balancer_data.port)
  return current_try
end


local function introspect_upstream_schema(service, request)
  local ip = service.host
  local host = service.host
  local port = service.port
  local path = service.path
  local protocol = service.protocol
  local headers = {
    ['content-type'] = "application/json",
    ['authorization'] = request.get_header("authorization")
  }

  local addr = ngx.ctx.balancer_data
  if addr == nil then
    return nil, "failed to get balancer data"
  end

  if addr.type == "name" then
    local opts = {
      host = ngx.var.upstream_host,
    }
    local try = get_peer(ngx.ctx, opts, ngx.var.upstream_scheme)
    ip = try.ip
    port = try.port
    host = opts.host
  end

  local httpc = http.new()
  local ok, c_err = httpc:connect(ip, port)
  if not ok then
    kong.log.err("failed to connect to ", ip, ":", tostring(port), ": ", c_err)
    return nil, c_err
  end

  if protocol == "https" then
    local _, h_err = httpc:ssl_handshake(true, host, false)
    if h_err then
      kong.log.err("failed to do SSL handshake with ",
              host, ":", tostring(port), ": ", h_err)
      return nil, h_err
    end
  end

  if ngx.var.upstream_host and ngx.var.upstream_host ~= "" then
    host = ngx.var.upstream_host
  end

  headers['host'] = host
  local introspection_req_body = cjson.encode({ query = GqlSchema.TYPE_INTROSPECTION_QUERY })
  local res, req_err = httpc:request {
    method = "POST",
    path = path,
    body = introspection_req_body,
    headers = headers,
  }

  if not res then
    kong.log.err("failed schema introspection request: ", req_err)
    return nil, req_err
  end

  local status = res.status
  local body = res:read_body()

  if status ~= 200 then
    kong.log.err("failed response from upstream server: introspect_upstream_schema return status: ", status, " body: ", body)
    return nil, { status = status, body = body }
  end

  local json = cjson.decode(body)
  local json_data = json["data"]

  if not json_data then
    kong.log.err("failed to introspect the schema, introspection response is in an unknown format")
    return nil, "failed to introspect schema"
  end

  kong.log.err("Schema Data from upstream server: ", json)

  local gql_schema = GqlSchema.deserialize_json_data(json_data)
  return true, gql_schema
end


function NewRLHandler:access(conf)
  local key = id_lookup[conf.identifier]()

  -- legacy logic, if authenticated consumer or credential is not found
  -- use the IP
  if not key then
    key = id_lookup["ip"]()
  end

  local deny

  -- if this worker has not yet seen the "rl:create" event propagated by the
  -- instatiation of a new plugin, create the namespace. in this case, the call
  -- to new_namespace in the registered rl handler will never be called on this
  -- worker
  --
  -- this workaround will not be necessary when real IPC is implemented for
  -- inter-worker communications
  if not ratelimiting.config[conf.namespace] then
    new_namespace(conf, true)
  end

  -- Introspecting query body to obtain GraphQL document and calculate its cost
  local body = kong.request.get_body()

  if not body or not body.query then
    kong.log.err("request body is empty or query was not provided")
    kong.response.exit(400, { message = "GraphQL query is missing"})
  end

  local gql_docstring = body.query

  local ok, res = pcall(build_ast, gql_docstring)
  if not ok then
    kong.log.err(res)
    return kong.response.exit(400, {
      err = "[GqlBaseErr]: internal parsing",
      message = res
    }, { ["Content-Type"] = "application/json" })
  end

  local service = ngx.ctx.service

  if not self.gql_schema[service.id] then -- Get upstream schema if needed
    local schema_ok, schema_res = introspect_upstream_schema(service, kong.request)
    if not schema_ok then
      return kong.response.exit(400, {
        message = "Failed to introspect upstream schema"
      })
    end

    self.gql_schema[service.id] = schema_res
  end


  local query_ast = res
  local gql_schema = self.gql_schema[service.id]

  local costs_db = kong.db.graphql_ratelimiting_advanced_cost_decoration

  for cost_dec in costs_db:each_for_service({ id = service.id }, 100) do
    query_ast:decorate_data({ cost_dec.type_path }, gql_schema, {
      add_arguments = cost_dec.add_arguments,
      add_constant = cost_dec.add_constant,
      mul_arguments = cost_dec.mul_arguments,
      mul_constant = cost_dec.mul_constant
    })
  end

  local query_cost = cost(query_ast, conf.cost_strategy)
  -- Reduce tota node cost quantified by conf.score_factor, min 1
  query_cost = math.ceil((query_cost + 0.01) * conf.score_factor)

  for i = 1, #conf.window_size do
    local window_size = tonumber(conf.window_size[i])
    local limit       = tonumber(conf.limit[i])

    -- if we have exceeded any rate, we should not increment any other windows,
    -- butwe should still show the rate to the client, maintaining a uniform
    -- set of response headers regardless of whether we block the request
    local rate
    if deny then
      rate = ratelimiting.sliding_window(key, window_size, nil, conf.namespace)

    else -- Increment cost window by computed cost of query
      rate = ratelimiting.increment(key, window_size, query_cost, conf.namespace,
                                    conf.window_type == "fixed" and 0 or nil)
    end

    -- legacy logic of naming rate limiting headers. if we configured a window
    -- size that looks like a human friendly name, give that name
    local window_name = human_window_size_lookup[window_size] or window_size

    if not conf.hide_client_headers then
      ngx.header["X-Gql-Query-Cost"] = query_cost
      ngx.header[RATELIMIT_LIMIT .. "-" .. window_name] = limit
      ngx.header[RATELIMIT_REMAINING .. "-" .. window_name] = max(limit - rate, 0)
    end

    if rate > limit then
      deny = true
    end
  end

  if conf.max_cost > 0 and query_cost > conf.max_cost then
    return kong.response.exit(403, { message = "API max cost limit exceeded" })
  end

  if deny then
    return kong.response.exit(429, { message = "API rate limit exceeded" })
  end
end


return NewRLHandler
