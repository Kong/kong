local new_tab = require "table.new"
local http = require "resty.http"
local clone = require "table.clone"
local otlp = require "kong.plugins.opentelemetry.otlp"
local propagation = require "kong.tracing.propagation"
local tablepool = require "tablepool"

local ngx = ngx
local kong = kong
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local ngx_req = ngx.req
local ngx_get_headers = ngx_req.get_headers
local timer_at = ngx.timer.at
local clear = table.clear
local propagation_parse = propagation.parse
local propagation_set = propagation.set
local tablepool_release = tablepool.release
local tablepool_fetch = tablepool.fetch
local null = ngx.null
local encode_traces = otlp.encode_traces
local transform_span = otlp.transform_span

local POOL_BATCH_SPANS = "KONG_OTLP_BATCH_SPANS"
local _log_prefix = "[otel] "

local OpenTelemetryHandler = {
  VERSION = "0.1.0",
  PRIORITY = 14,
}

local default_headers = {
  ["Content-Type"] = "application/x-protobuf",
}

-- worker-level spans queue
local spans_queue = new_tab(5000, 0)
local headers_cache = setmetatable({}, { __mode = "k" })
local last_run_cache = setmetatable({}, { __mode = "k" })

local function get_cached_headers(conf_headers)
  -- cache http headers
  local headers = default_headers
  if conf_headers then
    headers = headers_cache[conf_headers]
  end

  if not headers then
    headers = clone(default_headers)
    if conf_headers and conf_headers ~= null then
      for k, v in pairs(conf_headers) do
        headers[k] = v
      end
    end

    headers_cache[conf_headers] = headers
  end

  return headers
end


local function http_export_request(conf, pb_data, headers)
  local httpc = http.new()
  httpc:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)
  local res, err = httpc:request_uri(conf.endpoint, {
    method = "POST",
    body = pb_data,
    headers = headers,
  })
  if not res then
    ngx_log(ngx_ERR, _log_prefix, "failed to send request: ", err)
  end

  if res and res.status ~= 200 then
    ngx_log(ngx_ERR, _log_prefix, "response error: ", res.status, ", body: ", res.body)
  end
end

local function http_export(premature, conf)
  if premature then
    return
  end

  local spans_n = #spans_queue
  if spans_n == 0 then
    return
  end

  local start = ngx_now()
  local headers = conf.headers and get_cached_headers(conf.headers) or default_headers

  -- batch send spans
  local spans_buffer = tablepool_fetch(POOL_BATCH_SPANS, conf.batch_span_count, 0)

  for i = 1, spans_n do
    local len = (spans_buffer.n or 0) + 1
    spans_buffer[len] = spans_queue[i]
    spans_buffer.n = len

    if len >= conf.batch_span_count then
      local pb_data = encode_traces(spans_buffer, conf.resource_attributes)
      clear(spans_buffer)

      http_export_request(conf, pb_data, headers)
    end
  end

  -- remain spans
  if spans_queue.n and spans_queue.n > 0 then
    local pb_data = encode_traces(spans_buffer, conf.resource_attributes)
    http_export_request(conf, pb_data, headers)
  end

  -- clear the queue
  clear(spans_queue)

  tablepool_release(POOL_BATCH_SPANS, spans_buffer)

  ngx_update_time()
  local duration = ngx_now() - start
  ngx_log(ngx_DEBUG, _log_prefix, "opentelemetry exporter sent " .. spans_n ..
    " traces to " .. conf.endpoint .. " in " .. duration .. " seconds")
end

local function process_span(span)
  if span.should_sample == false
      or kong.ctx.plugin.should_sample == false
  then
    -- ignore
    return
  end

  -- overwrite
  local trace_id = kong.ctx.plugin.trace_id
  if trace_id then
    span.trace_id = trace_id
  end

  local pb_span = transform_span(span)

  local len = spans_queue.n or 0
  len = len + 1

  spans_queue[len] = pb_span
  spans_queue.n = len
end

function OpenTelemetryHandler:rewrite()
  local headers = ngx_get_headers()
  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]

  -- make propagation running with tracing instrumetation not enabled
  if not root_span then
    local tracer = kong.tracing.new("otel")
    root_span = tracer.start_span("root")

    -- the span created only for the propagation and will be bypassed to the exporter
    kong.ctx.plugin.should_sample = false
  end

  local header_type, trace_id, span_id, _, should_sample, _ = propagation_parse(headers)
  if should_sample == false then
    root_span.should_sample = should_sample
  end

  -- overwrite trace id
  if trace_id then
    root_span.trace_id = trace_id
    kong.ctx.plugin.trace_id = trace_id
  end

  -- overwrite root span's parent_id
  if span_id then
    root_span.parent_id = span_id
  end

  propagation_set("w3c", header_type, root_span)
end

function OpenTelemetryHandler:log(conf)
  ngx_log(ngx_DEBUG, _log_prefix, "total spans in current request: ", ngx.ctx.KONG_SPANS and #ngx.ctx.KONG_SPANS)

  -- transform spans
  kong.tracing.process_span(process_span)

  local cache_key = conf.__key__
  local last = last_run_cache[cache_key] or 0
  local now = ngx_now()
  if now - last >= conf.batch_flush_delay then
    last_run_cache[cache_key] = now
    timer_at(0, http_export, conf)
  end
end

return OpenTelemetryHandler
