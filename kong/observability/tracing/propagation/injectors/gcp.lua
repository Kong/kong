local _INJECTOR = require "kong.observability.tracing.propagation.injectors._base"
local bn        = require "resty.openssl.bn"
local to_hex    = require "resty.string".to_hex

local GCP_INJECTOR = _INJECTOR:new({
  name = "gcp",
  context_validate = {
    all = { "trace_id", "span_id" },
  },
  trace_id_allowed_sizes = { 16 },
  span_id_size_bytes = 8,
})


function GCP_INJECTOR:create_headers(out_tracing_ctx)
  return {
    ["x-cloud-trace-context"] = to_hex(out_tracing_ctx.trace_id) .. "/" ..
        bn.from_binary(out_tracing_ctx.span_id):to_dec() ..
        ";o=" .. (out_tracing_ctx.should_sample and "1" or "0")
  }
end


function GCP_INJECTOR:get_formatted_trace_id(trace_id)
  return { gcp = to_hex(trace_id) }
end


return GCP_INJECTOR
