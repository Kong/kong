-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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

  local header_type, trace_id, span_id, parent_id = propagation_parse(headers)

  if trace_id then
    root_span.trace_id = trace_id
  end

  if span_id then
    root_span.parent_id = span_id

  elseif parent_id then
    root_span.parent_id = parent_id
  end

  local new_span = ngx.ctx.last_try_balancer_span
  if new_span == nil then
    new_span = tracer.create_span(nil, {
      span_kind = 3,
      parent = root_span,
    })
    ngx.ctx.last_try_balancer_span = new_span
  end

  local type = header_type and "preserve" or "w3c"
  propagation_set(type, header_type, new_span, "trace-propagator")
end

return _M
