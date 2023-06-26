local _INJECTOR = require "kong.tracing.propagation.injectors._base"
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
      {
        name = "x-b3-traceid",
        value = to_hex(out_tracing_ctx.trace_id)
      },
      {
        name = "x-b3-spanid",
        value = to_hex(out_tracing_ctx.span_id)
      },
    }

    if out_tracing_ctx.parent_id then
      table.insert(headers, {
        name = "x-b3-parentspanid",
        value = to_hex(out_tracing_ctx.parent_id)
      })
    end

  else
    headers = {}
  end

  if out_tracing_ctx.flags then
    table.insert(headers, {
      name = "x-b3-flags",
      value = out_tracing_ctx.flags
    })

  else
    table.insert(headers, {
      name = "x-b3-sampled",
      value = out_tracing_ctx.should_sample and "1" or "0"
    })
  end

  return headers
end


function B3_INJECTOR:get_formatted_trace_id(trace_id)
  return { b3 = trace_id and to_hex(trace_id) or "" }
end


return B3_INJECTOR
