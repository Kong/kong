local _INJECTOR = require "kong.tracing.propagation.injectors._base"
local to_hex    = require "resty.string".to_hex

local OT_INJECTOR = _INJECTOR:new({
  name = "ot",
  context_validate = {
    all = { "trace_id", "span_id" },
  },
  trace_id_allowed_sizes = { 8, 16 },
  span_id_size_bytes = 8,
})


function OT_INJECTOR:create_headers(out_tracing_ctx)
  local headers = {
    {
      name = "ot-tracer-traceid",
      value = to_hex(out_tracing_ctx.trace_id)
    },
    {
      name = "ot-tracer-spanid",
      value = to_hex(out_tracing_ctx.span_id)
    },
  }

  if out_tracing_ctx.should_sample ~= nil then
    table.insert(headers, {
      name = "ot-tracer-sampled",
      value = out_tracing_ctx.should_sample and "1" or "0"
    })
  end

  local baggage = out_tracing_ctx.baggage
  if baggage then
    for k, v in pairs(baggage) do
      table.insert(headers, {
        name = "ot-baggage-" .. k,
        value = ngx.escape_uri(v)
      })
    end
  end

  return headers
end


function OT_INJECTOR:get_formatted_trace_id(trace_id)
  return { ot = to_hex(trace_id) }
end


return OT_INJECTOR
