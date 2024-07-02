local _INJECTOR = require "kong.observability.tracing.propagation.injectors._base"
local to_hex    = require "resty.string".to_hex

local B3_SINGLE_INJECTOR = _INJECTOR:new({
  name = "b3-single",
  context_validate = {}, -- all fields are optional
  trace_id_allowed_sizes = { 16, 8 },
  span_id_size_bytes = 8,
})


function B3_SINGLE_INJECTOR:create_headers(out_tracing_ctx)
  local sampled
  if out_tracing_ctx.flags == "1" then
    sampled = "d"
  elseif out_tracing_ctx.should_sample then
    sampled = "1"
  elseif out_tracing_ctx.should_sample == false then
    sampled = "0"
  end

  -- propagate sampling decision only
  -- see: https://github.com/openzipkin/b3-propagation/blob/master/RATIONALE.md#b3-single-header-format
  if not out_tracing_ctx.trace_id or not out_tracing_ctx.span_id then
    sampled = sampled or "0"

    return { b3 = sampled }
  end

  return {
    b3 = to_hex(out_tracing_ctx.trace_id) ..
        "-" .. to_hex(out_tracing_ctx.span_id) ..
        (sampled and "-" .. sampled or "") ..
        (out_tracing_ctx.parent_id and "-" .. to_hex(out_tracing_ctx.parent_id) or "")
  }
end


function B3_SINGLE_INJECTOR:get_formatted_trace_id(trace_id)
  return { b3 = trace_id and to_hex(trace_id) or "" }
end


return B3_SINGLE_INJECTOR
