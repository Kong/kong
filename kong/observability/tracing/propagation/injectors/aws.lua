local _INJECTOR = require "kong.observability.tracing.propagation.injectors._base"
local to_hex    = require "resty.string".to_hex

local sub         = string.sub

local AWS_TRACE_ID_VERSION = "1"
local AWS_TRACE_ID_TIMESTAMP_LEN = 8

local AWS_INJECTOR = _INJECTOR:new({
  name = "aws",
  context_validate = {
    all = { "trace_id", "span_id" },
  },
  trace_id_allowed_sizes = { 16 },
  span_id_size_bytes = 8,
})


function AWS_INJECTOR:create_headers(out_tracing_ctx)
  local trace_id = to_hex(out_tracing_ctx.trace_id)
  return {
    ["x-amzn-trace-id"] = "Root=" .. AWS_TRACE_ID_VERSION .. "-" ..
        sub(trace_id, 1, AWS_TRACE_ID_TIMESTAMP_LEN) .. "-" ..
        sub(trace_id, AWS_TRACE_ID_TIMESTAMP_LEN + 1, #trace_id) ..
        ";Parent=" .. to_hex(out_tracing_ctx.span_id) .. ";Sampled=" ..
        (out_tracing_ctx.should_sample and "1" or "0")
  }
end


function AWS_INJECTOR:get_formatted_trace_id(trace_id)
  return { aws = to_hex(trace_id) }
end


return AWS_INJECTOR
