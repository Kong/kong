-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local tracing = require "kong.pdk.tracing".new()
local buffer = require "string.buffer"
local tablepool = require "tablepool"
local base = require "resty.core.base"
local cjson = require "cjson"
local ngx_re = require "ngx.re"
local bit = require "bit"
local ngx_ssl = require("ngx.ssl")
local socket_instrum = require "kong.enterprise_edition.debug_session.instrumentation.socket"
local redis_instrum = require "kong.enterprise_edition.debug_session.instrumentation.redis"
local content_capture = require "kong.enterprise_edition.debug_session.instrumentation.content_capture"
local SPAN_ATTRIBUTES = require("kong.enterprise_edition.debug_session.instrumentation.attributes").SPAN_ATTRIBUTES
local utils = require "kong.enterprise_edition.debug_session.utils"
local latency_metrics = require "kong.enterprise_edition.debug_session.latency_metrics"
local request_id_get = require "kong.observability.tracing.request_id".get
local time_ns = require("kong.tools.time").time_ns

local tablepool_release = tablepool.release
local get_method = ngx.req.get_method
local ngx_get_phase = ngx.get_phase
local get_ctx_key = utils.get_ctx_key
local log = utils.log
local cjson_encode = cjson.encode
local new_tab = base.new_tab
local concat = table.concat
local split = ngx_re.split
local band = bit.band
local max = math.max
local bor = bit.bor
local var = ngx.var

local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR

local setmetatable = setmetatable
local tonumber = tonumber
local assert = assert
local pairs = pairs
local type = type
local ngx = ngx


local _M = {}
local tracer = tracing.new("noop", { noop = true })
local subtracer = tracer

local POOL_SPAN_STORAGE = get_ctx_key("SPAN_STORAGE")
local SESSION_ACTIVATING = get_ctx_key("session_activating")

local SPAN_KIND_SERVER = 2
local SPAN_KIND_CLIENT = 3

local INSTRUMENTATIONS = {
  off                  = 0x00000000,
  request              = 0x00000001,
  dns_query            = 0x00000002,
  router               = 0x00000004,
  http_client          = 0x00000008,
  balancer             = 0x00000010,
  plugin_certificate   = 0x00000020,
  plugin_rewrite       = 0x00000040,
  plugin_access        = 0x00000080,
  plugin_header_filter = 0x00000100,
  plugin_body_filter   = 0x00000200,
  plugin_response      = 0x00000400,
  debug                = 0x00000800,
  io                   = 0x00001000,
}

local all_instrums = 0x00000000
for _, instr in pairs(INSTRUMENTATIONS) do
  all_instrums = bor(all_instrums, instr)
end
INSTRUMENTATIONS.all = all_instrums

-- state of enabled instrumentations
local default_enabled_instrums = INSTRUMENTATIONS.off
local enabled_instrums = default_enabled_instrums

local SPAN_NAMES = {
  KONG = "kong",
  PHASE_CERTIFICATE = "kong.phase.certificate",
  PHASE_REWRITE = "kong.phase.rewrite",
  PHASE_ACCESS = "kong.phase.access",
  PHASE_HEADER_FILTER = "kong.phase.header_filter",
  PHASE_BODY_FILTER = "kong.phase.body_filter",
  PHASE_RESPONSE = "kong.phase.response",
  DNS = "kong.dns",
  ROUTER = "kong.router",
  HTTP_CLIENT = "kong.io.http.request",
  BALANCER_UPSTREAM_SELECTION = "kong.upstream.selection",
  BALANCER_UPSTREAM_TRY_SELECT = "kong.upstream.try_select",
  UPSTREAM_TTFB = "kong.upstream.ttfb",
  UPSTREAM_READ_RESPONSE = "kong.upstream.read_response",
  PLUGIN_CERTIFICATE = "kong.certificate.plugin",
  PLUGIN_REWRITE = "kong.rewrite.plugin",
  PLUGIN_ACCESS = "kong.access.plugin",
  PLUGIN_HEADER_FILTER = "kong.header_filter.plugin",
  PLUGIN_BODY_FILTER = "kong.body_filter.plugin",
  PLUGIN_RESPONSE = "kong.response.plugin",
  READ_BODY = "kong.read_client_http_body",
  CLIENT_HEADERS = "kong.read_client_http_headers",
  FLUSH_TO_DOWNSTREAM = "kong.wait_for_client_read",
  TLS_HANDSHAKE = "kong.tls_handshake",
}

local VALID_TRACING_PHASES = {
  ssl_cert = true,
  rewrite = true,
  access = true,
  header_filter = true,
  body_filter = true,
  log = true,
  content = true,
  balancer = true,
}


local function is_valid_phase()
  local phase = ngx_get_phase()
  return VALID_TRACING_PHASES[phase]
end


local function is_enabled(instrumentation)
  return band(enabled_instrums, instrumentation) ~= 0
end


local function should_skip_instrumentation(instrumentation)
  return not is_enabled(instrumentation)
end


local function set_session_activating()
  ngx.ctx[SESSION_ACTIVATING] = true
end


local function is_session_activating()
  return ngx.ctx[SESSION_ACTIVATING] == true
end


local function create_root_span(start_time, attributes)
  local root_span = tracer.start_span(SPAN_NAMES.KONG, {
    span_kind = SPAN_KIND_SERVER,
    start_time_ns = start_time,
    attributes = attributes,
  })
  tracer.set_active_span(root_span)
  return root_span
end


local function check_initialize_trace(start_time)
  if not is_valid_phase() then
    -- nothing to initialize
    return
  end

  start_time = start_time or time_ns()
  if not tracer.get_root_span() then
    create_root_span(start_time)
  end
end


local function start_subspan(...)
  if not is_valid_phase() then
    -- not in a request: ignore
    return
  end

  -- if a subspan is started while the session is starting, we skip it
  -- this avoids generating partial traces if a session is started mid-request
  if is_session_activating() then
    return nil, "session is activating"
  end
  -- ensure the subspan always has a parent (the trace must have a root span)
  check_initialize_trace()
  return tracer.start_span(...)
end


-- Record Router span
function _M.router()
  if should_skip_instrumentation(INSTRUMENTATIONS.router) then
    return
  end

  local span, err = subtracer.start_span(SPAN_NAMES.ROUTER)
  if not span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  subtracer.set_active_span(span)
  return span
end


function _M.balancer_upstream_selection(ctx)
  if should_skip_instrumentation(INSTRUMENTATIONS.balancer) then
    return
  end

  local balancer_data = ctx.balancer_data
  if not balancer_data then
    return
  end

  local balancer_tries = balancer_data.tries
  local try_count = balancer_data.try_count
  local first_try = balancer_tries[1]
  if not first_try or try_count == 0 then
    return
  end


  local first_try_start_ns = first_try.balancer_start_ns
  local upstream_selection_span_options = {
    span_kind = SPAN_KIND_CLIENT,
    start_time_ns = first_try_start_ns,
    parent = tracer.get_root_span(),
    attributes = {
      ["try_count"] = try_count,
    }
  }

  local upstream_selection_span, err = subtracer.start_span(SPAN_NAMES.BALANCER_UPSTREAM_SELECTION, upstream_selection_span_options)
  if not upstream_selection_span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  subtracer.set_active_span(upstream_selection_span)
  upstream_selection_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_LB_ALGORITHM, balancer_data.upstream and balancer_data.upstream.algorithm or "unknown")
  local upstream_id = balancer_data.upstream and balancer_data.upstream.id or "unknown"
  upstream_selection_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_ID, upstream_id)

  local upstream_connect_times = split(var.upstream_connect_time, ", ", "jo")
  local upstream_response_times = split(var.upstream_response_time, ", ", "jo")
  local upstream_header_times = split(var.upstream_header_time, ", ", "jo")

  local selected_upstream_total_response_time_ms
  local selected_upstream_connect_time_ms
  local selected_upstream_header_time_ms
  local selected_upstream_status_code
  local upstream_selection_finish_time_ns
  local selected_upstream_port
  local selected_upstream_ip
  local selected_upstream_target_id

  local first_upstream_start_connect_time

  -- unsuccessful tries
  for i = 1, try_count do
    local try = balancer_tries[i]
    local span_options = {
      span_kind = SPAN_KIND_CLIENT,
      start_time_ns = try.balancer_start_ns,
      attributes = {
        ["try_count"] =  i,
        [SPAN_ATTRIBUTES.NETWORK_PEER_ADDRESS] = try.ip,
        [SPAN_ATTRIBUTES.NETWORK_PEER_PORT]= try.port,
        [SPAN_ATTRIBUTES.HTTP_RESPONSE_STATUS_CODE] = try.code,
        ["keepalive"] = try.keepalive,
        [SPAN_ATTRIBUTES.KONG_TARGET_ID] = try.target_id,
      }
    }

    local span, err = subtracer.start_span(SPAN_NAMES.BALANCER_UPSTREAM_TRY_SELECT, span_options)
    if not span then
      if err then
        log(ngx_ERR, "failed to start span: ", err)
      end
      return
    end

    if try.state then
      span:set_attribute(SPAN_ATTRIBUTES.HTTP_RESPONSE_STATUS_CODE, try.code)
      span:set_status(2)
    end
    if balancer_data.hostname ~= nil then
      span:set_attribute(SPAN_ATTRIBUTES.NETWORK_PEER_NAME, balancer_data.hostname)
    end

    local try_upstream_connect_time_ms = (tonumber(upstream_connect_times[i], 10) or 0) * 1e3
    local try_upstream_response_time_ms = (tonumber(upstream_response_times[i], 10) or 0) * 1e3
    local try_upstream_header_time_ms = (tonumber(upstream_header_times[i], 10) or 0) * 1e3
    -- on the last try, ignore the response time: it is not part of "upstream selection"
    -- and is traced in a separate span
    selected_upstream_total_response_time_ms = try_upstream_response_time_ms
    selected_upstream_connect_time_ms = try_upstream_connect_time_ms
    selected_upstream_header_time_ms = try_upstream_header_time_ms
    selected_upstream_port = try.port
    selected_upstream_ip = try.ip
    selected_upstream_target_id = try.target_id
    if i == try_count then
      try_upstream_response_time_ms = 0
    end

    if i == 1 then
      -- store the first upstream connect time
      -- used later to generate the metric that records the total upstream time
      first_upstream_start_connect_time = try.balancer_start_ns / 1e6
    end

    local try_upstream_time = max(try_upstream_connect_time_ms, try_upstream_response_time_ms)
    upstream_selection_finish_time_ns = (try.balancer_start_ns + (try.balancer_latency_ns or 0) + try_upstream_time * 1e6)

    span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_CONNECT_DURATION_MS, try_upstream_connect_time_ms)
    if i ~= try_count then
      span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_RESPONSE_DURATION_MS, try_upstream_response_time_ms)
    end

    selected_upstream_status_code = try.code
    span:finish(upstream_selection_finish_time_ns)
  end

  upstream_selection_span:finish(upstream_selection_finish_time_ns)

  -- TTFB (Time to first byte) -> Time it takes for the upstream to respond with the first header(byte)
  local upstream_ttfb_start_time_ns = upstream_selection_finish_time_ns
  local upstream_ttfb_span, err = subtracer.start_span(SPAN_NAMES.UPSTREAM_TTFB, {
    span_kind = SPAN_KIND_CLIENT,
    start_time_ns = upstream_ttfb_start_time_ns,
  })
  if not upstream_ttfb_span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  local upstream_ttfb_ms = selected_upstream_header_time_ms - (selected_upstream_connect_time_ms or 0)
  -- Adjusting for time format
  local upstream_ttfb_finish_time_ns = upstream_ttfb_start_time_ns + upstream_ttfb_ms * 1e6
  upstream_ttfb_span:finish(upstream_ttfb_finish_time_ns)

  local upstream_read_response_start_time_ns = upstream_ttfb_finish_time_ns
  local upstream_response_span, err = subtracer.start_span(SPAN_NAMES.UPSTREAM_READ_RESPONSE, {
    span_kind = SPAN_KIND_CLIENT,
    start_time_ns = upstream_read_response_start_time_ns,
  })
  if not upstream_response_span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end

  -- The time it takes to read the response from the point we receive the first
  -- header to the end of the response (upstream_response_time_total - ttfb - connect_time)
  local upstream_read_response_duration_ms = max(0, selected_upstream_total_response_time_ms - upstream_ttfb_ms - selected_upstream_connect_time_ms)
  local upstream_read_response_end_time_ns = upstream_read_response_start_time_ns + upstream_read_response_duration_ms * 1e6
  upstream_response_span:finish(upstream_read_response_end_time_ns)

  -- generate the metric that records the total upstream time
  local ok, err = latency_metrics.set("upstream_latency", (upstream_read_response_end_time_ns / 1e6) - first_upstream_start_connect_time)
  if not ok then
    log(ngx_ERR, "failed to set upstream latency metric: ", err)
  end

  local root_span = tracer.get_root_span()
  if root_span then
    root_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_TTFB_MS, upstream_ttfb_ms)
    root_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_READ_RESPONSE_DURATION_MS, upstream_read_response_duration_ms)
    root_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_STATUS_CODE, selected_upstream_status_code)
    root_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_ID, upstream_id)
    root_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_ADDR, selected_upstream_ip)
    root_span:set_attribute(SPAN_ATTRIBUTES.KONG_UPSTREAM_HOST, selected_upstream_ip .. ":" .. selected_upstream_port)
    root_span:set_attribute(SPAN_ATTRIBUTES.KONG_TARGET_ID, selected_upstream_target_id)
    root_span:set_attribute(SPAN_ATTRIBUTES.NETWORK_PEER_PORT, selected_upstream_port)
    root_span:set_attribute(SPAN_ATTRIBUTES.NETWORK_PEER_ADDRESS, selected_upstream_ip)
  end
end


function _M.get_upstream_latency()
  local latency, err = latency_metrics.get("upstream_latency")
  if not latency then
    log(ngx_ERR, "failed to get upstream latency metric: ", err)
    return
  end
  return latency
end


function _M.wait_for_client_read(ctx)
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  local start_time = ctx.KONG_RESPONSE_ENDED_AT_NS
                     or ctx.KONG_RESPONSE_ENDED_AT and ctx.KONG_RESPONSE_ENDED_AT * 1e6
                     or ctx.KONG_BODY_FILTER_ENDED_AT_NS
  local end_time = ctx.KONG_LOG_START_NS or time_ns()

  local span, err = subtracer.start_span(SPAN_NAMES.FLUSH_TO_DOWNSTREAM, {
    span_kind = SPAN_KIND_SERVER,
    start_time_ns = start_time,
  })
  if not span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  span:finish(end_time)
  local ok, err = latency_metrics.add("client_latency", (end_time - start_time) / 1e6)
  if not ok then
    log(ngx_ERR, "failed to add client latency metric: ", err)
  end
end


function _M.get_client_latency()
  local latency, err = latency_metrics.get("client_latency")
  if not latency then
    log(ngx_ERR, "failed to get client latency metric: ", err)
    return
  end
  return latency
end


-- Generator for different plugin phases
local function plugin_callback(phase)
  local name_memo = {}

  return function(plugin, conf)
    if should_skip_instrumentation(INSTRUMENTATIONS["plugin_" .. phase]) then
      return
    end

    local plugin_name = plugin.name
    local name = name_memo[plugin_name]
    if not name then
      name = "kong." .. phase .. ".plugin." .. plugin_name
      name_memo[plugin_name] = name
    end

    local span, err = subtracer.start_span(name, {
      attributes = {
        [SPAN_ATTRIBUTES.KONG_PLUGIN_ID] = conf and conf.__plugin_id or nil,
      }
    })
    if not span then
      if err then
        log(ngx_ERR, "failed to start span: ", err)
      end
      return
    end
    subtracer.set_active_span(span)
    return span
  end
end

_M.plugin_certificate = plugin_callback("certificate")
_M.plugin_rewrite = plugin_callback("rewrite")
_M.plugin_access = plugin_callback("access")
_M.plugin_header_filter = plugin_callback("header_filter")
_M.plugin_response = plugin_callback("response")


_M.plugin_body_filter_before = function(plugin, conf)
  if should_skip_instrumentation(INSTRUMENTATIONS.plugin_body_filter) then
    return
  end

  local plugin_name = plugin.name
  local name = "kong.body_filter.plugin." .. plugin_name
  local body_filter_span_ctx_key = get_ctx_key("kong_spans:" .. name)

  -- body filter is called many times, ensure the span is only
  -- created once
  local span = ngx.ctx[body_filter_span_ctx_key]
  if not span then
    local err
    span, err = subtracer.start_span(name, {
      attributes = {
        [SPAN_ATTRIBUTES.KONG_PLUGIN_ID] = conf and conf.__plugin_id or nil,
      }
    })
    if not span then
      if err then
        log(ngx_ERR, "failed to start span: ", err)
      end
      return
    end
    subtracer.set_active_span(span)
    ngx.ctx[body_filter_span_ctx_key] = span
  end

  local plugins_body_filter_ctx_key = get_ctx_key("plugin_body_filter_spans")
  ngx.ctx[plugins_body_filter_ctx_key] = ngx.ctx[plugins_body_filter_ctx_key] or {}
  table.insert(ngx.ctx[plugins_body_filter_ctx_key], span)

  return span
end


_M.plugin_body_filter_after = function(span)
  if should_skip_instrumentation(INSTRUMENTATIONS.plugin_body_filter) then
    return
  end

  if not span then
    return
  end

  local chunks = span.attributes and span.attributes["chunks"] or {}
  local chunk_n = #chunks + 1
  local chunk_exec_time = time_ns() - span.start_time_ns
  table.insert(chunks, { execution_time = chunk_exec_time, chunk_n = chunk_n })
  -- TODO: Treat this as meta information or a Kong attribute?
  span:set_attribute("chunks", chunks)
  span:set_attribute("num_chunks", #chunks)

  -- if not EOF it is not time to finish this span yet
  if not ngx.arg[2] then
    return
  end

  if span then
    span:finish()
  end
end


-- finish all plugin body filter spans that were not finished
-- during the body filter phase
_M.plugins_body_filter_after = function(end_time)
  if should_skip_instrumentation(INSTRUMENTATIONS.plugin_body_filter) then
    return
  end

  local plugins_body_filter_ctx_key = get_ctx_key("plugin_body_filter_spans")
  local plugin_body_filter_spans = ngx.ctx[plugins_body_filter_ctx_key]
  if not plugin_body_filter_spans then
    return
  end

  for _, span in ipairs(plugin_body_filter_spans) do
    span:finish(end_time)
  end
end


--- Record HTTP client calls
-- This only record `resty.http.request_uri` method,
-- because it's the most common usage of lua-resty-http library.
function _M.http_client()
  local http = require "resty.http"
  local request_uri = http.request_uri
  local request = http.request

  local function get_wrapper(f)
    -- can be either:
    -- httpc:request(params)
    -- httpc:request_uri(uri, params)
    return function(self, arg1, arg2)
      if should_skip_instrumentation(INSTRUMENTATIONS.http_client) then
        return f(self, arg1, arg2)
      end

      local params = arg2 or arg1
      local uri = arg2 and arg1 or params.path

      local method = params and params.method or "GET"
      local attributes = new_tab(0, 5)
      -- passing full URI to http.url attribute
      attributes["http.url"] = uri
      attributes["http.method"] = method
      attributes["http.flavor"] = params and params.version or "1.1"
      attributes["http.user_agent"] = params and params.headers and params.headers["User-Agent"]
          or http._USER_AGENT

      local http_proxy = self.proxy_opts and (self.proxy_opts.https_proxy or self.proxy_opts.http_proxy)
      if http_proxy then
        attributes["http.proxy"] = http_proxy
      end

      local start_time = time_ns()
      local span, err = subtracer.start_span(SPAN_NAMES.HTTP_CLIENT, {
        span_kind = SPAN_KIND_CLIENT,
        attributes = attributes,
        start_time_ns = start_time,
      })
      if not span then
        if err then
          log(ngx_ERR, "failed to start span: ", err)
        end
        return f(self, arg1, arg2)
      end

      local res, err = f(self, arg1, arg2)
      if res then
        attributes["http.status_code"] = res.status -- number
      else
        span:record_error(err)
      end
      span:finish()

      -- Record total time spent doing HTTP client IO
      local ok, m_err = latency_metrics.add("http_client_total_time", (time_ns() - start_time) / 1e6)
      if not ok then
        log(ngx_ERR, "failed to add http client total time metric: ", m_err)
      end

      return res, err
    end
  end

  http.request_uri = get_wrapper(request_uri)
  http.request = get_wrapper(request)
end


function _M.get_total_http_client_time()
  local latency, err = latency_metrics.get("http_client_total_time")
  if not latency then
    log(ngx_ERR, "failed to get http client total time metric: ", err)
    return
  end
  return latency
end


function _M.certificate()
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    -- a trace that skips this instrumentation must be skipped because it
    -- misses the root span. This can happen if a debug session is started
    -- mid-request.
    set_session_activating()
    return
  end

  local start_time = time_ns()
  create_root_span(start_time)

  -- generate span for ssl_cert phase
  local span_phase_cert, err = subtracer.start_span(SPAN_NAMES.PHASE_CERTIFICATE, {
    start_time_ns = start_time,
    attributes = {
      ["tls.version"] = ngx_ssl.get_tls1_version_str() or "",
    }
  })
  if not span_phase_cert then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  subtracer.set_active_span(span_phase_cert)
  return span_phase_cert
end


local function initialize_trace(ctx)
  local start_time = ctx.KONG_PROCESSING_START
                 and ctx.KONG_PROCESSING_START * 1e6
                  or time_ns()
  check_initialize_trace(start_time)

  local client = kong.client
  local method = get_method()
  local scheme = ctx.scheme or var.scheme
  local host = var.host
  -- passing full URI to http.url attribute
  local req_uri = scheme .. "://" .. host .. (ctx.request_uri or var.request_uri)

  local http_flavor = ngx.req.http_version()
  if type(http_flavor) == "number" then
    http_flavor = string.format("%.1f", http_flavor)
  end

  local root_span = tracer.get_root_span()
  if not root_span then
    log(ngx_ERR, "missing root span")
    return
  end

  root_span:set_attribute(SPAN_ATTRIBUTES.REQUEST_METHOD, method)
  root_span:set_attribute(SPAN_ATTRIBUTES.URL_FULL, req_uri)
  -- TODO: is there an OTEL equivalent?
  root_span:set_attribute(SPAN_ATTRIBUTES.HTTP_HOST_HEADER, host)
  root_span:set_attribute(SPAN_ATTRIBUTES.URL_SCHEME, scheme)
  root_span:set_attribute(SPAN_ATTRIBUTES.NETWORK_PROTOCOL_VERSION, http_flavor)
  -- http is the only protocol supported by Active Tracing
  root_span:set_attribute(SPAN_ATTRIBUTES.NETWORK_PROTOCOL, "http")
  root_span:set_attribute(SPAN_ATTRIBUTES.CLIENT_ADDRESS, client.get_forwarded_ip())
  root_span:set_attribute(SPAN_ATTRIBUTES.NETWORK_PEER_ADDRESS, client.get_ip())
  root_span:set_attribute(SPAN_ATTRIBUTES.KONG_REQUEST_ID, request_id_get())
end


-- this is an approximation of the tls handshake time, which occurs
-- between the end of the certificate phase and the start of the request
-- It includes the time the client waited, after connecting, before
-- sending the request
local function tls_handshake(ctx)
  local start_time = ctx.connection and
                     ctx.connection.KONG_CERTIFICATE_ENDED_AT_NS
  if not start_time then
    return
  end

  local span, err = subtracer.start_span(SPAN_NAMES.TLS_HANDSHAKE, {
    span_kind = SPAN_KIND_SERVER,
    start_time_ns = start_time,
  })
  if not span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end

  ngx.update_time()
  local end_time = ngx.req.start_time() * 1e9
  span:finish(end_time)
end


local function client_headers()
  ngx.update_time()
  local start_time = ngx.req.start_time() * 1e9

  local headers_bytes = 0
  local headers_num = 0
  -- 1000 is the maximum num of headers we can get
  local headers, err = kong.request.get_headers(1000)
  if not headers then
    log(ngx_ERR, "failed to get request headers: ", err)
    return
  end
  for k, v in pairs(headers) do
    local val = type(v) == "table" and concat(v, "") or v
    headers_bytes = headers_bytes + #k + #(val or "")
    headers_num = headers_num + 1
  end

  local span, err = subtracer.start_span(SPAN_NAMES.CLIENT_HEADERS, {
    span_kind = SPAN_KIND_SERVER,
    start_time_ns = start_time,
    parent = tracer.get_root_span(),
    attributes = {
      [SPAN_ATTRIBUTES.KONG_HTTP_REQUEST_HEADER_COUNT] = headers_num,
      [SPAN_ATTRIBUTES.KONG_HTTP_REQUEST_HEADER_SIZE] = headers_bytes,
    }
  })
  if not span then
    log(ngx_ERR, "failed to start span: ", err)
    return
  end
  local end_time = time_ns()
  span:finish(end_time)
  local ok, err = latency_metrics.add("client_latency", (end_time - start_time) / 1e6)
  if not ok then
    log(ngx_ERR, "failed to add client latency metric: ", err)
  end
end


local function rewrite_phase()
  local rewrite_phase_span, err = subtracer.start_span(SPAN_NAMES.PHASE_REWRITE)
  if not rewrite_phase_span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  subtracer.set_active_span(rewrite_phase_span)
  return rewrite_phase_span
end


function _M.rewrite(ctx)
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    -- a trace that skips this instrumentation must be skipped because it
    -- misses the root span. This can happen if a debug session is started
    -- mid-request.
    set_session_activating()
    return
  end

  initialize_trace(ctx)
  tls_handshake(ctx)
  client_headers()

  return rewrite_phase()
end


function _M.access()
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  local access_phase_span, err = subtracer.start_span(SPAN_NAMES.PHASE_ACCESS)
  if not access_phase_span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  subtracer.set_active_span(access_phase_span)

  -- we are in access: we can capture request headers
  content_capture.request_headers()

  return access_phase_span
end


function _M.header_filter()
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  local header_filter_phase_span, err = subtracer.start_span(SPAN_NAMES.PHASE_HEADER_FILTER)
  if not header_filter_phase_span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  subtracer.set_active_span(header_filter_phase_span)

  return header_filter_phase_span
end


function _M.content_capture_response_headers()
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  content_capture.response_headers()
end


function _M.body_filter_before()
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  local span_ctx_key = get_ctx_key("kong_spans:body_filter")
  local span = ngx.ctx[span_ctx_key]
  if not span then
    local err
    span, err = subtracer.start_span(SPAN_NAMES.PHASE_BODY_FILTER)
    if not span then
      if err then
        log(ngx_ERR, "failed to start span: ", err)
      end
      return
    end
    subtracer.set_active_span(span)
    ngx.ctx[span_ctx_key] = span
  end

  return span
end


function _M.content_capture_response_body()
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  local ok, err = content_capture.response_body()
  if not ok and err then
    log(ngx_ERR, "content_capture failed to read response body: ", err)
  end
end


function _M.body_filter_after(end_time)
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  local span_ctx_key = get_ctx_key("kong_spans:body_filter")
  local span = ngx.ctx[span_ctx_key]
  if span then
    span:finish(end_time)
  end
end


function _M.response()
  if should_skip_instrumentation(INSTRUMENTATIONS.request) then
    return
  end

  local response_phase_span, err = subtracer.start_span(SPAN_NAMES.PHASE_RESPONSE)
  if not response_phase_span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end
  subtracer.set_active_span(response_phase_span)
  return response_phase_span
end


do
  local raw_func

  local function wrap(host, port, ...)
    if should_skip_instrumentation(INSTRUMENTATIONS.dns_query) then
      return raw_func(host, port, ...)
    end

    local start_time = time_ns()
    local span, err = subtracer.start_span(SPAN_NAMES.DNS, {
      span_kind = SPAN_KIND_CLIENT,
      start_time_ns = start_time,
    })
    if not span then
      if err then
        log(ngx_ERR, "failed to start span: ", err)
      end
      return raw_func(host, port, ...)
    end

    local ip_addr, res_port, try_list = raw_func(host, port, ...)
    if span then
      local ok, m_err = latency_metrics.add("dns_total_time", (time_ns() - start_time) / 1e6)
      if not ok then
        log(ngx_ERR, "failed to add dns total time metric: ", m_err)
      end

      span:set_attribute(SPAN_ATTRIBUTES.KONG_DNS_RECORD_DOMAIN, host)
      span:set_attribute(SPAN_ATTRIBUTES.KONG_DNS_RECORD_PORT, port)
      if try_list and #try_list > 0 then
        local tries = {}
        -- extract the array part of the try_list
        for i = 1, #try_list do
          tries[i] = try_list[i]
        end
        span:set_attribute(SPAN_ATTRIBUTES.KONG_DNS_TRIES, tries)
      end

      if ip_addr then
        span:set_attribute(SPAN_ATTRIBUTES.KONG_DNS_RECORD_IP, ip_addr)
      else
        span:record_error(res_port)
        span:set_status(2)
      end
      span:finish()
    end

    return ip_addr, res_port, try_list
  end

  --- Get Wrapped DNS Query
  -- Called before Kong's config loader.
  --
  -- returns a wrapper for the provided input function `f`
  -- that stores dns info in the `kong.dns` span when the dns
  -- instrumentation is enabled.
  function _M.get_wrapped_dns_query(f)
    raw_func = f
    return wrap
  end
end


function _M.get_total_dns_time()
  local ok, err = latency_metrics.get("dns_total_time")
  if not ok then
    log(ngx_ERR, "failed to get dns total time metric: ", err)
    return
  end
  return ok
end


-- runloop
function _M.runloop_before_header_filter()
  local root_span = tracer.get_root_span()
  if root_span then
    root_span:set_attribute(SPAN_ATTRIBUTES.HTTP_RESPONSE_STATUS_CODE, ngx.status)
    local r = ngx.ctx.route
    root_span:set_attribute(SPAN_ATTRIBUTES.URL_PATH, r and r.paths and r.paths[1] or "")
  end
end

function _M.get_root_span()
  return tracer.get_root_span()
end


function _M.runloop_log_before(ctx)
  -- set the root span end time to `log:before`
  local root_span_end_time = time_ns()

  -- add balancer selection time
  _M.balancer_upstream_selection(ctx)

  -- add wait_for_client_read span
  _M.wait_for_client_read(ctx)

  -- finish root span
  local root_span = tracer.get_root_span()
  if not root_span then
    return
  end

  root_span:finish(root_span_end_time)
end

-- serialize lazily
local lazy_format_spans
do
  local lazy_mt = {
    __tostring = function(spans)
      local logs_buf = buffer.new(1024)

      for i = 1, #spans do
        local span = spans[i]

        logs_buf:putf("\nSpan #%d name=%s", i, span.name)

        if span.end_time_ns then
          logs_buf:putf(" duration=%fms", (span.end_time_ns - span.start_time_ns) / 1e6)
        end

        if span.attributes then
          logs_buf:putf(" attributes=%s", cjson_encode(span.attributes))
        end
      end

      local str = logs_buf:get()

      logs_buf:free()

      return str
    end
  }

  lazy_format_spans = function(spans)
    return setmetatable(spans, lazy_mt)
  end
end

-- clean up
function _M.runloop_log_after(ctx)
  -- Clears the span table and put back the table pool,
  -- this avoids reallocation.
  -- The span table MUST NOT be used after released.
  local spans = tracer.get_spans()

  if type(spans) == "table" then
    log(ngx_DEBUG, "collected ", #spans, " spans: ", lazy_format_spans(spans))

    for i = 1, #spans do
      local span = spans[i]
      if type(span) == "table" and type(span.release) == "function" then
        span:release()
      end
    end

    tablepool_release(POOL_SPAN_STORAGE, spans)
  end
end


-- debug instrumentation: for debug session only
function _M.patch_read_body()
  local raw_func = ngx.req.read_body
  local function wrap()
    if should_skip_instrumentation(INSTRUMENTATIONS.debug) then
      return raw_func()
    end
    if not kong.debug_session or not kong.debug_session:is_active() then
      return raw_func()
    end

    local start_time = time_ns()
    local span, err = subtracer.start_span(SPAN_NAMES.READ_BODY, {
      span_kind = SPAN_KIND_SERVER,
      start_time_ns = start_time,
    })
    if not span then
      if err then
        log(ngx_ERR, "failed to start span: ", err)
      end
      return raw_func()
    end
    subtracer.set_active_span(span)

    -- mark the body as read for this request
    local body_read_ctx_key = get_ctx_key("body_read")
    ngx.ctx[body_read_ctx_key] = true

    raw_func()

    local end_time = time_ns()
    span:finish(end_time)
    local ok, err = latency_metrics.add("client_latency", (end_time - start_time) / 1e6)
    if not ok then
      log(ngx_ERR, "failed to add client latency metric: ", err)
    end
  end
  -- luacheck: globals ngx.req.read_body
  ngx.req.read_body = wrap
end


-- TODO: update this so it also finishes the access phase span
-- so we don't have to call both from the same places
function _M.access_end()
  if not kong.debug_session or not kong.debug_session:is_active() then
    return
  end

  local ok, err = content_capture.request_body()
  if not ok and err then
    log(ngx_ERR, "content_capture failed to read request body: ", err)
  end

  local access_ended_ctx_key = get_ctx_key("access_end")
  ngx.ctx[access_ended_ctx_key] = time_ns()
end


function _M.balancer_start()
  if not kong.debug_session or not kong.debug_session:is_active() then
    return
  end

  -- if the body was already read for this request return here 
  local body_read_ctx_key = get_ctx_key("body_read")
  if ngx.ctx[body_read_ctx_key] then
    return
  end

  -- else: the body was not read, so we need to create the span
  -- from the gap between access and balancer
  local access_ended_ctx_key = get_ctx_key("access_end")
  local access_ended_time = ngx.ctx[access_ended_ctx_key]
  if not access_ended_time then
    log(ngx_ERR, "access end time is missing")
    return
  end

  -- === RUN ONCE ===
  -- the balancer phase can execute multiple times
  -- the code below is only executed the first time
  local balancer_instrum_run_once = get_ctx_key("balancer_instrum_run_once")
  if ngx.ctx[balancer_instrum_run_once] then
    return
  end
  ngx.ctx[balancer_instrum_run_once] = true

  -- create the "read client body" span
  local start_time = tonumber(access_ended_time)
  local span, err = subtracer.start_span(SPAN_NAMES.READ_BODY, {
    span_kind = SPAN_KIND_SERVER,
    start_time_ns = start_time,
  })
  if not span then
    if err then
      log(ngx_ERR, "failed to start span: ", err)
    end
    return
  end

  local end_time = time_ns()
  span:finish(end_time)
  local ok, err = latency_metrics.add("client_latency", (end_time - start_time) / 1e6)
  if not ok then
    log(ngx_ERR, "failed to add client latency metric: ", err)
  end
end


function _M.copy_ssl_ctx_to_req_ctx(req_ctx, ssl_cert_ctx)
  -- copy spans table
  local spans_ctx_key = get_ctx_key("SPANS")
  local ssl_cert_ctx_spans = ssl_cert_ctx[spans_ctx_key]
  if type(ssl_cert_ctx_spans) == "table" and #ssl_cert_ctx_spans > 0 then
    req_ctx[spans_ctx_key] = ssl_cert_ctx_spans
  end

  -- copy active span
  local active_span_ctx_key = get_ctx_key("active_span")
  local ssl_cert_ctx_active_span = ssl_cert_ctx[active_span_ctx_key]
  if type(ssl_cert_ctx_active_span) == "table" then
    req_ctx[active_span_ctx_key] = ssl_cert_ctx_active_span
  end

  -- copy session activating
  req_ctx[SESSION_ACTIVATING] = ssl_cert_ctx[SESSION_ACTIVATING]

  -- clean up ssl_cert_ctx: we only use it once, for the first
  -- request of the current connection
  ssl_cert_ctx[spans_ctx_key] = nil
  ssl_cert_ctx[active_span_ctx_key] = nil
  ssl_cert_ctx[SESSION_ACTIVATING] = nil
end


function _M.instrument()
  socket_instrum.instrument()
  redis_instrum.instrument()
end


function _M.start_span(...)
  return subtracer.start_span(...)
end


function _M.foreach_span(...)
  return tracer.process_span(...)
end


function _M.get_spans()
  return tracer.get_spans()
end

-- TODO: this lookup can be improved, using a hash table
-- M2 is a good candidate to do this, if needed
function _M.get_span_by_name(span_name)
  local spans = tracer.get_spans()
  if not spans or type(spans) ~= "table" or #spans == 0 then
    return
  end

  -- typically we use this function to get an active span and finish it,
  -- so we loop backwards because the span we're looking for is
  -- likely to be one of the last ones
  for i = #spans, 1, -1 do
    local span = spans[i]
    if span.name == span_name then
      return span
    end
  end
end

_M.SPAN_NAMES = SPAN_NAMES
_M.INSTRUMENTATIONS = INSTRUMENTATIONS

_M.is_session_activating = is_session_activating
_M.should_skip_instrumentation = should_skip_instrumentation
_M.is_valid_phase = is_valid_phase

-- add an instrumentation to a bitmask of enabled instrumentations
-- @param number all_enabled the bitmask of all enabled instrumentations
-- @param string instr the instrumentation to add
local function add_instrum(all_enabled, instrum)
  local instrum_mask = INSTRUMENTATIONS[instrum]
  assert(instrum_mask, "unsupported instrumentation: " .. instrum)
  return bor(all_enabled, instrum_mask)
end


-- convert instrumentations array (as defined in kong.conf) to bitmask
-- @param table instrums_arr the array of instrumentations to be enabled enable
local function enabled_instrums_to_bitmask(instrums_arr)
  local enabled = 0
  local all_disabled = instrums_arr[1] == "off"

  -- TODO: support stream mode
  if all_disabled or ngx.config.subsystem == "stream" then
    return enabled
  end

  for _, instrum in ipairs(instrums_arr) do
    enabled = add_instrum(enabled, instrum)
  end

  -- enable request instrumentation by default if any other instrumentation
  -- is enabled: it is responsible for creating the root span
  if enabled ~= INSTRUMENTATIONS.off then
    enabled = bor(enabled, INSTRUMENTATIONS.request)
  end

  return enabled
end


local function init_tracer()
  local tracing_enabled = enabled_instrums ~= INSTRUMENTATIONS.off

  -- already initialized
  if tracing_enabled and tracer.name and tracer.name ~= "noop" then
    return
  end

  -- disable
  if not tracing_enabled then
    tracer = tracing.new("noop", { noop = true })
    subtracer = tracer
    return
  end

  -- initialize new tracer
  tracer = tracing.new("active-tracing", {
    sampling_rate = 1,
    namespace = utils.ctx_namespace,
  })

  -- tracer for managing spans that are not the root span
  -- it's a simple wrapper around the main tracer, which provides
  -- a convenience method to start spans safely by ensuring that
  -- the trace is initialized and the session is not starting
  subtracer = setmetatable({ start_span = start_subspan }, { __index = tracer })

  redis_instrum.init({ tracer = subtracer, instrum = _M })
  socket_instrum.init({ tracer = subtracer, instrum = _M })
end


-- sets the state of all the enabled instrumentations.
-- @param table instrums_default_arr the new enabled instrumentations
function _M.set(instrums_default_arr)
  enabled_instrums = enabled_instrums_to_bitmask(instrums_default_arr)
  init_tracer()
end


function _M.init(config)
  _M.set({ "off" }) -- initialize as disabled
end


return _M
