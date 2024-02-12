local Queue = require "kong.tools.queue"
local http = require "resty.http"
local clone = require "table.clone"
local otlp = require "kong.plugins.opentelemetry.otlp"
local propagation = require "kong.tracing.propagation"
local tracing_context = require "kong.tracing.tracing_context"


local ngx = ngx
local kong = kong
local tostring = tostring
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
local encode_span = otlp.transform_span
local to_hex = require "resty.string".to_hex


local _log_prefix = "[otel] "


local OpenTelemetryHandler = {
  VERSION = "0.1.0",
  PRIORITY = 14,
}

local CONTENT_TYPE_HEADER_NAME = "Content-Type"
local DEFAULT_CONTENT_TYPE_HEADER = "application/x-protobuf"
local DEFAULT_HEADERS = {
  [CONTENT_TYPE_HEADER_NAME] = DEFAULT_CONTENT_TYPE_HEADER
}

local function get_headers(conf_headers)
  if not conf_headers or conf_headers == null then
    return DEFAULT_HEADERS
  end

  if conf_headers[CONTENT_TYPE_HEADER_NAME] then
    return conf_headers
  end

  local headers = clone(conf_headers)
  headers[CONTENT_TYPE_HEADER_NAME] = DEFAULT_CONTENT_TYPE_HEADER
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
  local headers = get_headers(conf.headers)
  local payload = encode_traces(spans, conf.resource_attributes)

  local ok, err = http_export_request(conf, payload, headers)

  ngx_update_time()
  local duration = ngx_now() - start
  ngx_log(ngx_DEBUG, _log_prefix, "exporter sent ", #spans,
          " traces to ", conf.endpoint, " in ", duration, " seconds")

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err)
  end

  return ok, err
end

function OpenTelemetryHandler:access(conf)
  local headers = ngx_get_headers()
  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]

  -- get the global tracer when available, or instantiate a new one
  local tracer = kong.tracing.name == "noop" and kong.tracing.new("otel")
                 or kong.tracing

  -- make propagation work with tracing disabled
  if not root_span then
    root_span = tracer.start_span("root")
    root_span:set_attribute("kong.propagation_only", true)

    -- since tracing is disabled, turn off sampling entirely for this trace
    kong.ctx.plugin.should_sample = false
  end

  local injected_parent_span = tracing_context.get_unlinked_span("balancer") or root_span
  local header_type, trace_id, span_id, parent_id, parent_sampled, _ = propagation_parse(headers, conf.header_type)

  -- Overwrite trace ids
  -- with the value extracted from incoming tracing headers
  if trace_id then
    -- to propagate the correct trace ID we have to set it here
    -- before passing this span to propagation.set()
    injected_parent_span.trace_id = trace_id
    -- update the Tracing Context with the trace ID extracted from headers
    tracing_context.set_raw_trace_id(trace_id)
  end
  -- overwrite root span's parent_id
  if span_id then
    root_span.parent_id = span_id

  elseif parent_id then
    root_span.parent_id = parent_id
  end

  -- Configure the sampled flags
  local sampled
  if kong.ctx.plugin.should_sample == false then
    sampled = false

  else
    -- Sampling decision for the current trace.
    local err
    -- get_sampling_decision() depends on the value of the trace id: call it
    -- after the trace_id is updated
    sampled, err = tracer:get_sampling_decision(parent_sampled, conf.sampling_rate)
    if err then
      ngx_log(ngx_ERR, _log_prefix, "sampler failure: ", err)
    end
  end
  tracer:set_should_sample(sampled)
  -- Set the sampled flag for the outgoing header's span
  injected_parent_span.should_sample = sampled

  propagation_set(conf.header_type, header_type, injected_parent_span, "w3c")
end


function OpenTelemetryHandler:header_filter(conf)
  if conf.http_response_header_for_traceid then
    local trace_id = tracing_context.get_raw_trace_id()
    if not trace_id then
      local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
      trace_id = root_span and root_span.trace_id
    end
    if trace_id then
      trace_id = to_hex(trace_id)
      kong.response.add_header(conf.http_response_header_for_traceid, trace_id)
    end
  end
end


function OpenTelemetryHandler:log(conf)
  ngx_log(ngx_DEBUG, _log_prefix, "total spans in current request: ", ngx.ctx.KONG_SPANS and #ngx.ctx.KONG_SPANS)

  kong.tracing.process_span(function (span)
    if span.should_sample == false or kong.ctx.plugin.should_sample == false then
      -- ignore
      return
    end

    -- overwrite
    local trace_id = tracing_context.get_raw_trace_id()
    if trace_id then
      span.trace_id = trace_id
    end

    local ok, err = Queue.enqueue(
      Queue.get_plugin_params("opentelemetry", conf),
      http_export,
      conf,
      encode_span(span)
    )
    if not ok then
      kong.log.err("Failed to enqueue span to log server: ", err)
    end
  end)
end


return OpenTelemetryHandler
