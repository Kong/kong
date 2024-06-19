local _INJECTOR = require "kong.observability.tracing.propagation.injectors._base"
local bn        = require "resty.openssl.bn"

local from_binary = bn.from_binary

local DATADOG_INJECTOR = _INJECTOR:new({
  name = "datadog",
  context_validate = {}, -- all fields are optional
  -- TODO: support 128-bit trace IDs
  -- see: https://docs.datadoghq.com/tracing/guide/span_and_trace_id_format/#128-bit-trace-ids
  -- and: https://github.com/DataDog/dd-trace-py/pull/7181/files
  -- requires setting the `_dd.p.tid` span attribute
  trace_id_allowed_sizes = { 8 },
  span_id_size_bytes = 8,
})


function DATADOG_INJECTOR:create_headers(out_tracing_ctx)
  local headers = {
    ["x-datadog-trace-id"] = out_tracing_ctx.trace_id and
        from_binary(out_tracing_ctx.trace_id):to_dec() or nil,
    ["x-datadog-parent-id"] = out_tracing_ctx.span_id and
        from_binary(out_tracing_ctx.span_id):to_dec()
        or nil,
  }

  if out_tracing_ctx.should_sample ~= nil then
    headers["x-datadog-sampling-priority"] = out_tracing_ctx.should_sample and "1" or "0"
  end

  return headers
end


function DATADOG_INJECTOR:get_formatted_trace_id(trace_id)
  return { datadog = trace_id and from_binary(trace_id):to_dec() or nil }
end


return DATADOG_INJECTOR
