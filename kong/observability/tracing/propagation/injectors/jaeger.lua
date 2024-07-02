local _INJECTOR = require "kong.observability.tracing.propagation.injectors._base"
local to_hex    = require "resty.string".to_hex

local pairs = pairs
local ngx_escape_uri = ngx.escape_uri

local JAEGER_INJECTOR = _INJECTOR:new({
  name = "jaeger",
  context_validate = {
    all = { "trace_id", "span_id" },
  },
  trace_id_allowed_sizes = { 16, 8 },
  span_id_size_bytes = 8,
})


function JAEGER_INJECTOR:create_headers(out_tracing_ctx)
  local headers = {
    ["uber-trace-id"] = string.format("%s:%s:%s:%s",
        to_hex(out_tracing_ctx.trace_id),
        to_hex(out_tracing_ctx.span_id),
        out_tracing_ctx.parent_id and to_hex(out_tracing_ctx.parent_id) or "0",
        out_tracing_ctx.should_sample and "01" or "00")
  }

  local baggage = out_tracing_ctx.baggage
  if baggage then
    for k, v in pairs(baggage) do
      headers["uberctx-" .. k] = ngx_escape_uri(v)
    end
  end

  return headers
end


function JAEGER_INJECTOR:get_formatted_trace_id(trace_id)
  return { jaeger = to_hex(trace_id) }
end


return JAEGER_INJECTOR
