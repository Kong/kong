local propagation = require "kong.tracing.propagation"
local tracing_context = require "kong.tracing.tracing_context"

local ngx = ngx
local kong = kong
local propagation_parse = propagation.parse
local propagation_set = propagation.set

local _M = {
  PRIORITY = 1001,
  VERSION = "1.0",
}


function _M:access(conf)
  local headers = ngx.req.get_headers()
  local tracer = kong.tracing.name == "noop" and kong.tracing.new("otel")
                 or kong.tracing
  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
  if not root_span then
    root_span = tracer.start_span("root")
    root_span:set_attribute("kong.propagation_only", true)
    kong.ctx.plugin.should_sample = false
  end

  local injected_parent_span = tracing_context.get_unlinked_span("balancer") or root_span

  local header_type, trace_id, span_id, parent_id, parent_sampled = propagation_parse(headers)

  -- overwrite trace ids
  -- with the value extracted from incoming tracing headers
  if trace_id then
    injected_parent_span.trace_id = trace_id
    tracing_context.set_raw_trace_id(trace_id)
  end
  if span_id then
    root_span.parent_id = span_id
  elseif parent_id then
    root_span.parent_id = parent_id
  end

  -- Set the sampled flag for the outgoing header's span
  local sampled
  if kong.ctx.plugin.should_sample == false then
    sampled = false
  else
    sampled = tracer:get_sampling_decision(parent_sampled, conf.sampling_rate)
    tracer:set_should_sample(sampled)
  end
  injected_parent_span.should_sample = sampled

  local type = header_type and "preserve" or "w3c"
  propagation_set(type, header_type, injected_parent_span, "w3c")
end

return _M
