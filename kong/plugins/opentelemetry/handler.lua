local BatchQueue = require "kong.tools.batch_queue"
local http = require "resty.http"
local clone = require "table.clone"
local otlp = require "kong.plugins.opentelemetry.otlp"
local propagation = require "kong.tracing.propagation"

local pairs = pairs

local ngx = ngx
local kong = kong
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local ngx_req = ngx.req
local ngx_get_headers = ngx_req.get_headers
local propagation_parse = propagation.parse
local propagation_set = propagation.set
local null = ngx.null
local encode_traces = otlp.encode_traces
local translate_span_trace_id = otlp.translate_span
local encode_span = otlp.transform_span

local _log_prefix = "[otel] "

local OpenTelemetryHandler = {
  VERSION = "0.1.0",
  PRIORITY = 14,
}

local default_headers = {
  ["Content-Type"] = "application/x-protobuf",
}

-- worker-level spans queue
local queues = {} -- one queue per unique plugin config
local headers_cache = setmetatable({}, { __mode = "k" })

local function get_cached_headers(conf_headers)
  if not conf_headers then
    return default_headers
  end

  -- cache http headers
  local headers = headers_cache[conf_headers]

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
    return false, "failed to send request: " .. err

  elseif res and res.status ~= 200 then
    return false, "response error: " .. tostring(res.status) .. ", body: " .. tostring(res.body)
  end

  return true
end

local function http_export(conf, spans)
  local start = ngx_now()
  local headers = get_cached_headers(conf.headers)
  local payload = encode_traces(spans, conf.resource_attributes)

  local ok, err = http_export_request(conf, payload, headers)

  ngx_update_time()
  local duration = ngx_now() - start
  ngx_log(ngx_DEBUG, _log_prefix, "exporter sent " .. #spans ..
    " traces to " .. conf.endpoint .. " in " .. duration .. " seconds")

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err)
  end

  return ok, err
end

local function process_span(span, queue)
  if span.should_sample == false or kong.ctx.plugin.should_sample == false then
    -- ignore
    return
  end

  -- overwrite
  local trace_id = kong.ctx.plugin.trace_id
  if trace_id then
    span.trace_id = trace_id
  end

  local pb_span = encode_span(span)

  queue:add(pb_span)
end

function OpenTelemetryHandler:access()
  local headers = ngx_get_headers()
  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]

  -- make propagation running with tracing instrumetation not enabled
  if not root_span then
    local tracer = kong.tracing.new("otel")
    root_span = tracer.start_span("root")

    -- the span created only for the propagation and will be bypassed to the exporter
    kong.ctx.plugin.should_sample = false
  end

  local header_type, trace_id, span_id, parent_id, should_sample, _ = propagation_parse(headers)
  if should_sample == false then
    root_span.should_sample = should_sample
  end

  -- overwrite trace id
  -- as we are in a chain of existing trace
  if trace_id then
    root_span.trace_id = trace_id
    kong.ctx.plugin.trace_id = trace_id
  end

  -- overwrite root span's parent_id
  if span_id then
    root_span.parent_id = span_id

  elseif parent_id then
    root_span.parent_id = parent_id
  end

  propagation_set("preserve", header_type, translate_span_trace_id(root_span), "w3c")
end

function OpenTelemetryHandler:header_filter(conf)
  if conf.http_response_header_for_traceid then
    local trace_id = kong.ctx.plugin.trace_id
    if not trace_id then
      local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
      trace_id = root_span and root_span.trace_id
    end
    kong.response.add_header(conf.http_response_header_for_traceid, trace_id)
  end
end

function OpenTelemetryHandler:log(conf)
  ngx_log(ngx_DEBUG, _log_prefix, "total spans in current request: ", ngx.ctx.KONG_SPANS and #ngx.ctx.KONG_SPANS)

  local queue_id = conf.__key__
  local q = queues[queue_id]
  if not q then
    local process = function(entries)
      return http_export(conf, entries)
    end

    local opts = {
      batch_max_size = conf.batch_span_count,
      process_delay  = conf.batch_flush_delay,
    }

    local err
    q, err = BatchQueue.new("opentelemetry", process, opts)
    if not q then
      kong.log.err("could not create queue: ", err)
      return
    end
    queues[queue_id] = q
  end

  kong.tracing.process_span(process_span, q)
end

return OpenTelemetryHandler
