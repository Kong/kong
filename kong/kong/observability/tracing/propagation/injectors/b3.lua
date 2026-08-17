local _INJECTOR = require "kong.observability.tracing.propagation.injectors._base"
local to_hex    = require "resty.string".to_hex

local B3_INJECTOR = _INJECTOR:new({
  name = "b3",
  context_validate = {}, -- all fields are optional
  trace_id_allowed_sizes = { 16, 8 },
  span_id_size_bytes = 8,
})


function B3_INJECTOR:create_headers(out_tracing_ctx)
  local headers
  if out_tracing_ctx.trace_id and out_tracing_ctx.span_id then
    headers = {
      ["x-b3-traceid"] = to_hex(out_tracing_ctx.trace_id),
      ["x-b3-spanid"] = to_hex(out_tracing_ctx.span_id),
    }

    if out_tracing_ctx.parent_id then
      headers["x-b3-parentspanid"] = to_hex(out_tracing_ctx.parent_id)
    end

  else
    headers = {}
  end

  if out_tracing_ctx.flags then
    headers["x-b3-flags"] = out_tracing_ctx.flags

  else
    headers["x-b3-sampled"] = out_tracing_ctx.should_sample and "1" or "0"
  end

  return headers
end


function B3_INJECTOR:get_formatted_trace_id(trace_id)
  return { b3 = trace_id and to_hex(trace_id) or "" }
end


return B3_INJECTOR
