local propagation = require "kong.tracing.propagation"

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
  local tracer = kong.tracing.new("trace-propagator")
  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
  if not root_span then
    root_span = tracer.start_span("root")
  end
  local injected_parent_span = ngx.ctx.tracing and
                               ngx.ctx.tracing.injected.balancer_span or root_span

  local header_type, trace_id, span_id, parent_id, should_sample = propagation_parse(headers)

  if should_sample == false then
    tracer:set_should_sample(should_sample)
    injected_parent_span.should_sample = should_sample
  end

  if trace_id then
    injected_parent_span.trace_id = trace_id
  end

  if span_id then
    injected_parent_span.parent_id = span_id

  elseif parent_id then
    injected_parent_span.parent_id = parent_id
  end

  local type = header_type and "preserve" or "w3c"
  propagation_set(type, header_type, injected_parent_span, "w3c")
end

return _M
