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
  local root_span = tracer.start_span("root")

  local header_type, trace_id, span_id, parent_id, should_sample = propagation_parse(headers)

  if should_sample == false then
    tracer:set_should_sample(should_sample)
  end

  if trace_id then
    root_span.trace_id = trace_id
  end

  if span_id then
    root_span.parent_id = span_id

  elseif parent_id then
    root_span.parent_id = parent_id
  end

  local balancer_span = tracer.create_span(nil, {
    span_kind = 3,
    parent = root_span,
  })
  local type = header_type and "preserve" or "w3c"
  propagation_set(type, header_type, balancer_span, "w3c", true)
end

return _M
