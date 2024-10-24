local Queue = require "kong.tools.queue"
local propagation = require "kong.observability.tracing.propagation"
local tracing_context = require "kong.observability.tracing.tracing_context"
local otlp = require "kong.observability.otlp"
local otel_utils = require "kong.plugins.opentelemetry.utils"
local clone = require "table.clone"

local to_hex = require "resty.string".to_hex
local bor = require "bit".bor

local ngx = ngx
local kong = kong
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG

local http_export_request = otel_utils.http_export_request
local get_headers = otel_utils.get_headers
local _log_prefix = otel_utils._log_prefix
local encode_traces = otlp.encode_traces
local encode_span = otlp.transform_span


local function get_inject_ctx(extracted_ctx, conf)
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
  local trace_id = extracted_ctx.trace_id
  local span_id = extracted_ctx.span_id
  local parent_id = extracted_ctx.parent_id
  local parent_sampled = extracted_ctx.should_sample
  local flags = extracted_ctx.w3c_flags or extracted_ctx.flags

  -- Overwrite trace ids
  -- with the value extracted from incoming tracing headers
  if trace_id then
    -- to propagate the correct trace ID we have to set it here
    -- before passing this span to propagation
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

  extracted_ctx.trace_id      = injected_parent_span.trace_id
  extracted_ctx.span_id       = injected_parent_span.span_id
  extracted_ctx.should_sample = injected_parent_span.should_sample
  extracted_ctx.parent_id     = injected_parent_span.parent_id

  flags = flags or 0x00
  local sampled_flag = sampled and 1 or 0
  local out_flags = bor(flags,  sampled_flag)
  tracing_context.set_flags(out_flags)

  -- return the injected ctx (data to be injected with outgoing tracing headers)
  return extracted_ctx
end


local function access(conf)
  propagation.propagate(
    propagation.get_plugin_params(conf),
    get_inject_ctx,
    conf
  )
end


local function header_filter(conf)
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


local function http_export_traces(conf, spans)
  local headers = get_headers(conf.headers)
  local payload = encode_traces(spans, conf.resource_attributes)

  local ok, err = http_export_request({
    connect_timeout = conf.connect_timeout,
    send_timeout = conf.send_timeout,
    read_timeout = conf.read_timeout,
    endpoint = conf.traces_endpoint,
  }, payload, headers)

  if ok then
    ngx_log(ngx_DEBUG, _log_prefix, "exporter sent ", #spans,
          " spans to ", conf.traces_endpoint)

  else
    ngx_log(ngx_ERR, _log_prefix, err)
  end

  return ok, err
end


local function log(conf)
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

    local queue_conf = clone(Queue.get_plugin_params("opentelemetry", conf))
    queue_conf.name = queue_conf.name .. ":traces"

    local ok, err = Queue.enqueue(
      queue_conf,
      http_export_traces,
      conf,
      encode_span(span)
    )
    if not ok then
      kong.log.err("Failed to enqueue span to log server: ", err)
    end
  end)
end


return {
  access = access,
  header_filter = header_filter,
  log = log,
}
