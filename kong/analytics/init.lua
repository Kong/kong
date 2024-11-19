-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local reports            = require("kong.reports")
local new_tab            = require("table.new")
local request_id         = require("kong.observability.tracing.request_id")
local telemetry_dispatcher = require ("kong.clustering.telemetry_dispatcher")
local Queue              = require("kong.tools.queue")
local pb                 = require("pb")
local protoc             = require("protoc")
local at_instrumentation = require("kong.enterprise_edition.debug_session.instrumentation")

local is_http_module    = ngx.config.subsystem == "http"
local log               = ngx.log
local INFO              = ngx.INFO
local DEBUG             = ngx.DEBUG
local ERR               = ngx.ERR
local WARN              = ngx.WARN
local ngx               = ngx
local ngx_var           = ngx.var
local ngx_header        = ngx.header
local kong              = kong
local knode             = (kong and kong.node) and kong.node or
                            require("kong.pdk.node").new()
local re_gmatch         = ngx.re.gmatch
local ipairs            = ipairs
local assert            = assert
local to_hex            = require("resty.string").to_hex
local table_insert      = table.insert
local table_concat      = table.concat
local string_find       = string.find
local string_sub        = string.sub
local Queue_can_enqueue = Queue.can_enqueue
local Queue_enqueue     = Queue.enqueue
local get_rl_header     = require("kong.pdk.private.rate_limiting").get_stored_response_header

local _log_prefix                         = "[analytics] "
local DEFAULT_ANALYTICS_BUFFER_SIZE_LIMIT = 100000
local DEFAULT_ANALYTICS_FLUSH_INTERVAL    = 1
local KONG_VERSION                        = kong.version


local _M = {}
local _MT = { __index = _M }


local p = protoc.new()
p.include_imports = true
-- the file is uploaded by the build job
p:addpath("/usr/local/kong/include")
-- path for unit tests
p:addpath("kong/include")
p:loadfile("kong/model/analytics/payload.proto")

local LOG_SERILIZER_OPTS = {
  __skip_fetch_headers__ = true,
}

local function strip_query(str)
  local idx = string_find(str, "?", 1, true)
  if idx then
    return string_sub(str, 1, idx - 1)
  end

  return str
end


function _M.new(config)
  assert(config, "conf can not be nil", 2)

  local self = {
    cluster_endpoint = kong.configuration.cluster_telemetry_endpoint,
    path = "analytics/reqlog",
    reporter = nil,
    queue_conf = {
      name = "konnect_analytics_queue",
      log_tag = "konnect_analytics_queue",
      max_batch_size = 200,
      max_coalescing_delay = config.flush_interval or DEFAULT_ANALYTICS_FLUSH_INTERVAL,
      max_entries = config.analytics_buffer_size_limit or DEFAULT_ANALYTICS_BUFFER_SIZE_LIMIT,
      max_bytes = nil,
      initial_retry_delay = 0.2,
      max_retry_time = 60,
      max_retry_delay = 60,
      concurrency_limit = 1,
    }
  }

  return setmetatable(self, _MT)
end


function _M:random(low, high)
  return low + math.random() * (high - low);
end


local function get_server_name()
  local conf = kong.configuration
  local server_name

  -- server_name will be set to the host if it is not explicitly defined here
  if conf.cluster_telemetry_server_name ~= "" then
    server_name = conf.cluster_telemetry_server_name
  elseif conf.cluster_server_name ~= "" then
    server_name = conf.cluster_server_name
  end

  return server_name
end


function _M:init_worker()
  if not kong.configuration.konnect_mode then
    log(INFO, _log_prefix, "the analytics feature is only available to Konnect users.")
    return false
  end

  if not is_http_module then
    log(INFO, _log_prefix, "the analytics don't need to init in non HTTP module.")
    return false
  end

  if self:is_reporter_initialized() then
    log(WARN, _log_prefix, "tried to initialize kong.analytics (already initialized)")
    return true
  end

  log(INFO, _log_prefix, "init analytics workers.")

  -- can't define constant for node_id and node_hostname
  -- they will cause rbac integration tests to fail
  local uri = "wss://" .. self.cluster_endpoint .. "/v1/" .. self.path ..
    "?node_id=" .. knode.get_id() ..
    "&node_hostname=" .. knode.get_hostname() ..
    "&node_version=" .. KONG_VERSION

  local server_name = get_server_name()

  self.reporter = assert(telemetry_dispatcher.new({
    name = "analytics",
    server_name = server_name,
    uri = uri,
    pb_def_empty = "kong.model.analytics.Payload",
  }))
  self.reporter:init_connection()

  if ngx.worker.id() == 0 then
    reports.add_ping_value("konnect_analytics", true)
  end

  return true
end


function _M:is_reporter_initialized()
  return self.reporter and self.reporter:is_initialized()
end


function _M:is_reporter_running()
  return self.reporter and self.reporter:is_running()
end


function _M:enabled()
  return kong.configuration.konnect_mode and
         self:is_reporter_initialized() and self:is_reporter_running()
end


function _M:register_config_change(events_handler)
  events_handler.register(function(data, event, source, pid)
    log(INFO, _log_prefix, "config change event, incoming analytics: ",
      kong.configuration.konnect_mode)

    if kong.configuration.konnect_mode then
      if not self:is_reporter_initialized() then
        self:init_worker()
      end
      if not self:is_reporter_running() then
        self:start()
      end
    elseif self:is_reporter_running() then
      self:stop()
    end

  end, "kong:configuration", "change")
end

function _M:start()
  if not self.reporter then
    return nil, "reporter not initialized"
  end
  self.reporter:start()
end

function _M:stop()
  if not self.reporter then
    return nil, "reporter not initialized"
  end
  self.reporter:stop()
end


function _M:safe_string(var)
  if var == nil then
    return var
  end

  local tpe = type(var)
  if tpe == "string" then
    return var
  elseif tpe == "table" then
    return table_concat(var, ",")
  end

  return tostring(var)
end


function _M:create_payload(message)
  -- declare the table here for optimization
  local payload = {
    client_ip = "",
    started_at = 0,
    trace_id = "",
    active_tracing_trace_id = "",
    request_id = "",
    upstream = {
      upstream_uri = ""
    },
    request = {
      header_user_agent = "",
      header_host = "",
      http_method = "",
      body_size = 0,
      uri = ""
    },
    response = {
      http_status = 0,
      body_size = 0,
      header_content_length = 0,
      header_content_type = "",
      header_ratelimit_limit = 0,
      header_ratelimit_remaining = 0,
      header_ratelimit_reset = 0,
      header_retry_after = 0,
      header_x_ratelimit_limit_second = 0,
      header_x_ratelimit_limit_minute = 0,
      header_x_ratelimit_limit_hour = 0,
      header_x_ratelimit_limit_day = 0,
      header_x_ratelimit_limit_month = 0,
      header_x_ratelimit_limit_year = 0,
      header_x_ratelimit_remaining_second = 0,
      header_x_ratelimit_remaining_minute = 0,
      header_x_ratelimit_remaining_hour = 0,
      header_x_ratelimit_remaining_day = 0,
      header_x_ratelimit_remaining_month = 0,
      header_x_ratelimit_remaining_year = 0,
      ratelimit_enabled = false,
      ratelimit_enabled_second = false,
      ratelimit_enabled_minute = false,
      ratelimit_enabled_hour = false,
      ratelimit_enabled_day = false,
      ratelimit_enabled_month = false,
      ratelimit_enabled_year = false

    },
    route = {
      id = "",
      name = "",
      control_plane_id = ""
    },
    service = {
      id = "",
      name = "",
      port = 0,
      protocol = ""
    },
    latencies = {
      kong_gateway_ms = 0,
      upstream_ms = 0,
      response_ms = 0,
      receive_ms = 0,
    },
    tries = {},
    consumer = {
      id = "",
    },
    auth = {
      id = "",
      type = ""
    },
    upstream_status = "",
    source = "",
    application_context = {
      application_id = "",
      portal_id = "",
      organization_id = "",
      developer_id = "",
      product_version_id = "",
      authorization_scope_id = "",
    },
    consumer_groups = {},
    websocket = false,
    sse = false,
    ai = {},
    threats = {},
  }

  payload.client_ip = message.client_ip
  payload.started_at = message.started_at

  local ngx_ctx = ngx.ctx
  local root_span = ngx_ctx.KONG_SPANS and ngx_ctx.KONG_SPANS[1]
  local trace_id = root_span and root_span.trace_id
  if trace_id and root_span.should_sample then
    log(DEBUG, _log_prefix, "Attaching raw trace_id of to_hex(trace_id): ", to_hex(trace_id))
    payload.trace_id = trace_id
  end

  -- active tracing
  local at_root_span = at_instrumentation.get_root_span()
  local at_trace_id = at_root_span and at_root_span.trace_id
  if at_trace_id then
    log(DEBUG, _log_prefix, "Attaching raw active tracing trace_id of to_hex(trace_id): ", to_hex(at_trace_id))
    payload.active_tracing_trace_id = at_trace_id
  end

  local request_id_value, err = request_id.get()
  if request_id_value then
    payload.request_id = request_id_value

  else
    log(WARN, _log_prefix, "failed to get request id: ", err)
  end

  if message.upstream_uri ~= nil then
    payload.upstream.upstream_uri = strip_query(message.upstream_uri)
  end

  if message.request ~= nil then
    local request = payload.request
    local req = message.request

    -- Since Nginx 1.23.0,
    -- Nginx Variables combined duplicated headers using comma-separated string
    -- For example:
    -- X-Foo: 1
    -- X-Foo: 2
    -- X-Foo: 3
    -- And the `ngx_var.http_x_foo` will be `"1, 2, 3"`
    request.header_user_agent = ngx_var.http_user_agent
    request.header_host = ngx_var.http_host

    request.http_method = req.method
    request.body_size = req.size
    request.uri = strip_query(req.uri)
  end

  if message.response ~= nil then
    local response = payload.response
    local resp = message.response
    response.http_status = resp.status
    response.body_size = resp.size
    response.header_content_length = tonumber(ngx_header.content_length)
    response.header_content_type = ngx_header.content_type

    local ratelimit_limit = get_rl_header(ngx_ctx, "RateLimit-Limit")
    if ratelimit_limit then
      response.header_ratelimit_limit = ratelimit_limit
      response.header_ratelimit_remaining = get_rl_header(ngx_ctx, "RateLimit-Remaining")
      response.header_ratelimit_reset = get_rl_header(ngx_ctx, "RateLimit-Reset")
      response.ratelimit_enabled = true

    else
      response.header_ratelimit_limit = nil
      response.header_ratelimit_remaining = nil
      response.header_ratelimit_reset = nil
    end

    response.header_retry_after = get_rl_header(ngx_ctx, "Retry-After")

    local x_ratelimit_limit_second = get_rl_header(ngx_ctx, "X-RateLimit-Limit-Second")
    if x_ratelimit_limit_second then
      response.header_x_ratelimit_limit_second = x_ratelimit_limit_second
      response.header_x_ratelimit_remaining_second = get_rl_header(ngx_ctx, "X-RateLimit-Remaining-Second")
      response.ratelimit_enabled_second = true

    else
      response.header_x_ratelimit_limit_second = nil
      response.header_x_ratelimit_remaining_second = nil
    end

    local x_ratelimit_limit_minute = get_rl_header(ngx_ctx, "X-RateLimit-Limit-Minute")
    if x_ratelimit_limit_minute then
      response.header_x_ratelimit_limit_minute = x_ratelimit_limit_minute
      response.header_x_ratelimit_remaining_minute = get_rl_header(ngx_ctx, "X-RateLimit-Remaining-Minute")
      response.ratelimit_enabled_minute = true

    else
      response.header_x_ratelimit_limit_minute = nil
      response.header_x_ratelimit_remaining_minute = nil
    end

    local x_ratelimit_limit_hour = get_rl_header(ngx_ctx, "X-RateLimit-Limit-Hour")
    if x_ratelimit_limit_hour then
      response.header_x_ratelimit_limit_hour = x_ratelimit_limit_hour
      response.header_x_ratelimit_remaining_hour = get_rl_header(ngx_ctx, "X-RateLimit-Remaining-Hour")
      response.ratelimit_enabled_hour = true

    else
      response.header_x_ratelimit_limit_hour = nil
      response.header_x_ratelimit_remaining_hour = nil
    end

    local x_ratelimit_limit_day = get_rl_header(ngx_ctx, "X-RateLimit-Limit-Day")
    if x_ratelimit_limit_day then
      response.header_x_ratelimit_limit_day = x_ratelimit_limit_day
      response.header_x_ratelimit_remaining_day = get_rl_header(ngx_ctx, "X-RateLimit-Remaining-Day")
      response.ratelimit_enabled_day = true

    else
      response.header_x_ratelimit_limit_day = nil
      response.header_x_ratelimit_remaining_day = nil
    end

    local x_ratelimit_limit_month = get_rl_header(ngx_ctx, "X-RateLimit-Limit-Month")
    if x_ratelimit_limit_month then
      response.header_x_ratelimit_limit_month = x_ratelimit_limit_month
      response.header_x_ratelimit_remaining_month = get_rl_header(ngx_ctx, "X-RateLimit-Remaining-Month")
      response.ratelimit_enabled_month = true

    else
      response.header_x_ratelimit_limit_month = nil
      response.header_x_ratelimit_remaining_month = nil
    end

    local x_ratelimit_limit_year = get_rl_header(ngx_ctx, "X-RateLimit-Limit-Year")
    if x_ratelimit_limit_year then
      response.header_x_ratelimit_limit_year = x_ratelimit_limit_year
      response.header_x_ratelimit_remaining_year = get_rl_header(ngx_ctx, "X-RateLimit-Remaining-Year")
      response.ratelimit_enabled_year = true

    else
      response.header_x_ratelimit_limit_year = nil
      response.header_x_ratelimit_remaining_year = nil
    end

    local upgrade = ngx_header.upgrade
    local connection = ngx_header.connection
    if type(upgrade)      == "string"     and
       type(connection)   == "string"     and
       upgrade:lower()    == "websocket"  and
       connection:lower() == "upgrade"
    then
      payload.websocket = true
    end

    local content_type = ngx_header.content_type
    if type(content_type)   == "string" and
       content_type:lower() == "text/event-stream"
    then
      payload.sse = true
    end
  end

  if message.route ~= nil then
    local route = payload.route
    local tags = message.route.tags
    local tags_len = tags and #tags or 0
    if tags_len > 0 then
      local last_tag = tags[tags_len]
      local substr = last_tag:sub(1, 11)

      if substr == "cluster_id:" then -- eagerly extract the rest of the string
        route.control_plane_id = last_tag:sub(12, -1)
      end
    end
    route.id = message.route.id
    route.name = message.route.name
  end

  if message.service ~= nil then
    local service = payload.service
    local svc = message.service
    service.id = svc.id
    service.name = svc.name
    service.port = svc.port
    service.protocol = svc.protocol
  end

  if message.latencies ~= nil then
    local latencies = payload.latencies
    local ml = message.latencies
    latencies.kong_gateway_ms = ml.kong or 0
    latencies.upstream_ms = ml.proxy
    latencies.response_ms = ml.request
    latencies.receive_ms = ml.receive
  end

  if message.tries ~= nil then
    local tries = new_tab(#message.tries, 0)
    for i, try in ipairs(message.tries) do
      tries[i] = {
        balancer_latency = try.balancer_latency,
        ip = try.ip,
        port = try.port
      }
    end

    payload.tries = tries
  end

  if message.consumer ~= nil then
    local consumer = payload.consumer
    consumer.id = message.consumer.id
  end

  -- auth_type is only not nil when konnect-application-auth plugin is enabled
  -- authenticated_entity should only be collected when the plugin is enabled
  if message.auth_type ~= nil then
    local auth = payload.auth
    auth.type = message.auth_type
    if message.authenticated_entity ~= nil then
      auth.id = message.authenticated_entity.id
    end
  end

  if message.upstream_status ~= nil then
    payload.upstream_status = self:safe_string(message.upstream_status)
  end
  if message.source ~= nil then
    payload.source = message.source
  end

  local app_context = kong.ctx.shared.kaa_application_context
  if app_context then
    local app = payload.application_context
    app.application_id = app_context.application_id or ""
    app.portal_id = app_context.portal_id or ""
    app.organization_id = app_context.organization_id or ""
    app.developer_id = app_context.developer_id or ""
    app.product_version_id = app_context.product_version_id or ""
    app.authorization_scope_id = app_context.authorization_scope_id or ""
  end

  local consumer_groups = kong.client.get_consumer_groups()
  if consumer_groups then
    for _, v in ipairs(consumer_groups) do
      table_insert(payload.consumer_groups, { id = v.id })
    end
  end

  if message.ai ~= nil then
    payload.ai = self:transform_ai_data(message.ai)
  end

  if message.threats ~= nil then
    payload.threats = message.threats
  end

  return payload
end

function _M:transform_ai_data(ai_data)
  local transformed_ai_data = {}

  for plugin_name, plugin_ai_data in pairs(ai_data) do
      table.insert(transformed_ai_data, {
          plugin_name = plugin_name,
          usage = plugin_ai_data.usage,
          meta = plugin_ai_data.meta,
          cache = plugin_ai_data.cache,
      })
  end

  return transformed_ai_data
end

function _M:split(str, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = new_tab(2, 0)
  local i = 1
  for m, _ in re_gmatch(str, "([^" .. sep .. "]+)", "jo") do
    t[i] = m[0]
    i = i + 1
  end
  return t
end


local function encode_and_send(conf, data)
  local reporter = conf.reporter
  local payload = assert(pb.encode("kong.model.analytics.Payload", {
    data = data,
  }))

  return reporter:send(payload)
end


function _M:log_request()
  if not self:enabled() then
    return
  end

  local queue_conf = self.queue_conf

  if not Queue_can_enqueue(queue_conf) then
    log(WARN, _log_prefix, "Local buffer size limit reached for the analytics request log. ",
        "The current limit is ", queue_conf.max_entries)
    return
  end

  local handler_conf = {
    reporter = self.reporter,
  }

  local ok, err = Queue_enqueue(
    queue_conf,
    encode_and_send,
    handler_conf,
    self:create_payload(kong.log.serialize(LOG_SERILIZER_OPTS))
  )

  if not ok then
    log(ERR, _log_prefix, "failed to log request: ", err)
  end
end


return _M
