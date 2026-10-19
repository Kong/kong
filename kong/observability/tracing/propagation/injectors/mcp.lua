local _INJECTOR        = require "kong.observability.tracing.propagation.injectors._base"
local propagation_utils = require "kong.observability.tracing.propagation.utils"
local to_hex            = require "resty.string".to_hex

local string_format      = string.format
local type               = type
local format_w3c_baggage = propagation_utils.format_w3c_baggage

local MCP_INJECTOR = _INJECTOR:new({
  name = "mcp",
  context_validate = {
    all = { "trace_id", "span_id" },
  },
  trace_id_allowed_sizes = { 16 },
  span_id_size_bytes = 8,
})

--- Creates an MCP _meta table suitable for injection into params._meta or request._meta.
--
-- @function create_meta
-- @param table out_tracing_ctx Tracing context containing trace_id, span_id, should_sample, baggage, tracestate
-- @return table meta Table with traceparent and optional tracestate and baggage
local function create_meta(out_tracing_ctx)
  local trace_id = to_hex(out_tracing_ctx.trace_id)
  local span_id  = to_hex(out_tracing_ctx.span_id)
  local sampled  = out_tracing_ctx.should_sample and "01" or "00"

  local meta = {
    traceparent = string_format("00-%s-%s-%s", trace_id, span_id, sampled)
  }

  if out_tracing_ctx.tracestate and type(out_tracing_ctx.tracestate) == "string" and out_tracing_ctx.tracestate ~= "" then
    meta.tracestate = out_tracing_ctx.tracestate
  end

  if out_tracing_ctx.baggage then
    if type(out_tracing_ctx.baggage) == "table" then
      meta.baggage = format_w3c_baggage(out_tracing_ctx.baggage)
    elseif type(out_tracing_ctx.baggage) == "string" and out_tracing_ctx.baggage ~= "" then
      meta.baggage = out_tracing_ctx.baggage
    end
  end

  return meta
end

function MCP_INJECTOR:create_headers(out_tracing_ctx)
  return create_meta(out_tracing_ctx)
end

function MCP_INJECTOR:get_formatted_trace_id(trace_id)
  trace_id = to_hex(trace_id)
  return { mcp = trace_id }
end

MCP_INJECTOR.create_meta = create_meta

return MCP_INJECTOR
