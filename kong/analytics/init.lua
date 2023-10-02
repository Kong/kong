-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local reports = require "kong.reports"
local new_tab = require "table.new"
local cjson = require "cjson.safe"
local math = require "math"
local request_id = require "kong.tracing.request_id"
local log = ngx.log
local INFO = ngx.INFO
local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local WARN = ngx.WARN
local ngx = ngx
local kong = kong
local knode = (kong and kong.node) and kong.node or
  require "kong.pdk.node".new()
local timer_at = ngx.timer.at
local re_gmatch = ngx.re.gmatch
local ipairs = ipairs
local assert = assert
local _log_prefix = "[analytics] "
local persistence_handler
local DELAY_LOWER_BOUND = 0
local DELAY_UPPER_BOUND = 3
local DEFAULT_ANALYTICS_FLUSH_INTERVAL = 1
local DEFAULT_ANALYTICS_BUFFER_SIZE_LIMIT = 100000
local KONG_VERSION = kong.version
local to_hex = require "resty.string".to_hex

local table_insert = table.insert
local table_remove = table.remove
local clear_tab = require "table.clear"


local _M = {
}

local mt = { __index = _M }
local pb = require "pb"
local protoc = require "protoc"

local p = protoc.new()
p.include_imports = true
-- the file is uploaded by the build job
p:addpath("/usr/local/kong/include")
-- path for unit tests
p:addpath("kong/include")
p:loadfile("kong/model/analytics/payload.proto")

local EMPTY_PAYLOAD = pb.encode("kong.model.analytics.Payload", {})

function _M.new(config)
  assert(config, "conf can not be nil", 2)

  local self = {
    flush_interval = config.analytics_flush_interval or DEFAULT_ANALYTICS_FLUSH_INTERVAL,
    buffer_size_limit = config.analytics_buffer_size_limit or DEFAULT_ANALYTICS_BUFFER_SIZE_LIMIT,
    requests_buffer = {},
    requests_count = 0,
    cluster_endpoint = kong.configuration.cluster_telemetry_endpoint,
    path = "analytics/reqlog",
    ws_send_func = nil,
    running = false,
  }

  return setmetatable(self, mt)
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

  if self.initialized then
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
  local clustering = kong.clustering or require("kong.clustering").new(kong.configuration)

  assert(ngx.timer.at(0, clustering.telemetry_communicate, clustering, uri, server_name, function(connected, send_func)
    if connected then
      ngx.log(ngx.INFO, _log_prefix, "worker id: " .. ngx.worker.id() .. ". analytics websocket is connected: " .. uri)
      self.ws_send_func = send_func

    else
      ngx.log(ngx.INFO, _log_prefix, "worker id: " .. ngx.worker.id() .. ". analytics websocket is disconnected: " .. uri)
      self.ws_send_func = nil
    end
  end), nil)

  self.initialized = true
  self:start()

  if ngx.worker.id() == 0 then
    reports.add_ping_value("konnect_analytics", true)
  end

  return true
end

function _M:enabled()
  return kong.configuration.konnect_mode and self.initialized and self.running
end

function _M:register_config_change(events_handler)
  events_handler.register(function(data, event, source, pid)
    log(INFO, _log_prefix, "config change event, incoming analytics: ",
      kong.configuration.konnect_mode)

    if kong.configuration.konnect_mode then
      if not self.initialized then
        self:init_worker()
      end
      if not self.running then
        self:start()
      end
    elseif self.running then
      self:stop()
    end

  end, "kong:configuration", "change")
end

function _M:start()

  local when = self.flush_interval + self:random(DELAY_LOWER_BOUND, DELAY_UPPER_BOUND)
  log(DEBUG, _log_prefix, "starting initial analytics timer in ", when, " seconds")

  local ok, err = timer_at(when, persistence_handler, self)
  if ok then
    log(INFO, _log_prefix, "initial analytics timers started. flush interval: ",
      self.flush_interval, " seconds. max buffer size: ", self.buffer_size_limit)
    self.running = true

  else
    log(ERR, _log_prefix, "failed to start the initial analytics timer ", err)
  end
end

function _M:stop()
  log(INFO, _log_prefix, "stopping analytics")
  self.running = false
end

persistence_handler = function(premature, self)
  if premature then
    return
  end

  -- do not run / re schedule timer when not running (hot reload)
  if not self.running then
    log(INFO, _log_prefix, "stopping timer; persistence handler")
    return
  end

  local when = self.flush_interval + self:random(DELAY_LOWER_BOUND, DELAY_UPPER_BOUND)
  log(DEBUG, _log_prefix, "starting recurring analytics timer in " .. when .. " seconds for worker " .. ngx.worker.id())

  local ok, err = timer_at(when, persistence_handler, self)
  if not ok then
    return nil, "failed to start recurring analytics timer: " .. err
  end

  self:flush_data()
end

function _M:flush_data()
  if not self.ws_send_func then
    return
  end

  if self.requests_count == 0 then
    -- send a dummy to keep the connection open.
    self.ws_send_func(EMPTY_PAYLOAD)
    return
  end

  if kong.configuration.analytics_debug then
    log(INFO, _log_prefix, "analytics_debug: " .. cjson.encode(self.requests_buffer))
  end

  log(DEBUG, _log_prefix, "flushing analytics request log data: " .. #self.requests_buffer .. ". worker id: " .. ngx.worker.id())

  local bytes = pb.encode("kong.model.analytics.Payload", {
    data = self.requests_buffer,
  })
  self.ws_send_func(bytes)
  clear_tab(self.requests_buffer)
  self.requests_count = 0
end

function _M:create_payload(message)
  -- declare the table here for optimization
  local payload = {
    client_ip = "",
    started_at = 0,
    trace_id = "",
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
      name = ""
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
      response_ms = 0
    },
    tries = {},
    consumer = {
      id = "",
    },
    auth = {
      id = "",
      type = ""
    }
  }

  payload.client_ip = message.client_ip
  payload.started_at = message.started_at

  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
  local trace_id = root_span and root_span.trace_id
  if trace_id and root_span.should_sample then
    log(DEBUG, _log_prefix, "Attaching raw trace_id of to_hex(trace_id): ", to_hex(trace_id))
    payload.trace_id = trace_id
  end

  local request_id_value, err = request_id.get()
  if request_id_value then
    payload.request_id = request_id_value

  else
    log(WARN, _log_prefix, "failed to get request id: ", err)
  end

  if message.upstream_uri ~= nil then
    payload.upstream.upstream_uri = self:split(message.upstream_uri, "?")[1]
  end

  if message.request ~= nil then
    local request = payload.request
    local req = message.request
    request.header_user_agent = req.headers["user-agent"]
    request.header_host = req.headers["host"]
    request.http_method = req.method
    request.body_size = req.size
    request.uri = self:split(req.uri, "?")[1]
  end

  if message.response ~= nil then
    local response = payload.response
    local resp = message.response
    response.http_status = resp.status
    response.body_size = resp.size
    response.header_content_length = resp.headers["content-length"]
    response.header_content_type = resp.headers["content-type"]
    response.header_ratelimit_limit = tonumber(resp.headers["ratelimit-limit"])
    response.header_ratelimit_remaining = tonumber(resp.headers["ratelimit-remaining"])
    response.header_ratelimit_reset = tonumber(resp.headers["ratelimit-reset"])
    response.header_retry_after = tonumber(resp.headers["retry-after"])
    response.header_x_ratelimit_limit_second = tonumber(resp.headers["x-ratelimit-limit-second"])
    response.header_x_ratelimit_limit_minute = tonumber(resp.headers["x-ratelimit-limit-minute"])
    response.header_x_ratelimit_limit_hour = tonumber(resp.headers["x-ratelimit-limit-hour"])
    response.header_x_ratelimit_limit_day = tonumber(resp.headers["x-ratelimit-limit-day"])
    response.header_x_ratelimit_limit_month = tonumber(resp.headers["x-ratelimit-limit-month"])
    response.header_x_ratelimit_limit_year = tonumber(resp.headers["x-ratelimit-limit-year"])
    response.header_x_ratelimit_remaining_second = tonumber(resp.headers["x-ratelimit-remaining-second"])
    response.header_x_ratelimit_remaining_minute = tonumber(resp.headers["x-ratelimit-remaining-minute"])
    response.header_x_ratelimit_remaining_hour = tonumber(resp.headers["x-ratelimit-remaining-hour"])
    response.header_x_ratelimit_remaining_day = tonumber(resp.headers["x-ratelimit-remaining-day"])
    response.header_x_ratelimit_remaining_month = tonumber(resp.headers["x-ratelimit-remaining-month"])
    response.header_x_ratelimit_remaining_year = tonumber(resp.headers["x-ratelimit-remaining-year"])
    if resp.headers["ratelimit-limit"] ~= nil then
      response.ratelimit_enabled = true
    end
    if resp.headers["x-ratelimit-limit-second"] ~= nil then
      response.ratelimit_enabled_second = true
    end
    if resp.headers["x-ratelimit-limit-minute"] ~= nil then
      response.ratelimit_enabled_minute = true
    end
    if resp.headers["x-ratelimit-limit-hour"] ~= nil then
      response.ratelimit_enabled_hour = true
    end
    if resp.headers["x-ratelimit-limit-day"] ~= nil then
      response.ratelimit_enabled_day = true
    end
    if resp.headers["x-ratelimit-limit-month"] ~= nil then
      response.ratelimit_enabled_month = true
    end
    if resp.headers["x-ratelimit-limit-year"] ~= nil then
      response.ratelimit_enabled_year = true
    end
  end

  if message.route ~= nil then
    local route = payload.route
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
    latencies.kong_gateway_ms = ml.kong
    latencies.upstream_ms = ml.proxy
    latencies.response_ms = ml.request
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

  return payload
end

function _M:split(str, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = new_tab(2, 0)
  local i = 1
  for m, _ in re_gmatch(str, "([^" .. sep .. "]+)") do
    t[i] = m[0]
    i = i + 1
  end
  return t
end

function _M:log_request()
  if not self:enabled() then
    return
  end

  if self.requests_count > self.buffer_size_limit then
    log(WARN, _log_prefix, "Local buffer size limit reached for the analytics request log. " ..
      "The current limit is " .. self.buffer_size_limit)
    table_remove(self.requests_buffer, 1)
    self.requests_count = self.requests_count - 1
  end
  local message = kong.log.serialize()
  local payload = self:create_payload(message)
  table_insert(self.requests_buffer, payload)
  self.requests_count = self.requests_count + 1
end

return _M
