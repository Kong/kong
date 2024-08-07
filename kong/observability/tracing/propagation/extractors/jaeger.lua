local _EXTRACTOR               = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils        = require "kong.observability.tracing.propagation.utils"

local from_hex                 = propagation_utils.from_hex
local parse_baggage_headers    = propagation_utils.parse_baggage_headers
local match                    = string.match
local type = type
local tonumber = tonumber

local JAEGER_TRACECONTEXT_PATTERN = "^(%x+):(%x+):(%x+):(%x+)$"
local JAEGER_BAGGAGE_PATTERN      = "^uberctx%-(.*)$"

local JAEGER_EXTRACTOR            = _EXTRACTOR:new({
  headers_validate = {
    any = { "uber-trace-id" }
  }
})


function JAEGER_EXTRACTOR:get_context(headers)
  local jaeger_header = headers["uber-trace-id"]

  if type(jaeger_header) ~= "string" or jaeger_header == "" then
    return
  end

  local trace_id, span_id, parent_id, trace_flags = match(jaeger_header, JAEGER_TRACECONTEXT_PATTERN)

  -- values are not parsable hexidecimal and therefore invalid.
  if trace_id == nil or span_id == nil or parent_id == nil or trace_flags == nil then
    kong.log.warn("invalid jaeger uber-trace-id header; ignoring.")
    return
  end

  -- valid trace_id is required.
  if #trace_id > 32 or tonumber(trace_id, 16) == 0 then
    kong.log.warn("invalid jaeger trace ID; ignoring.")
    return
  end

  -- validating parent_id. If it is invalid just logging, as it can be ignored
  -- https://www.jaegertracing.io/docs/1.29/client-libraries/#tracespan-identity
  if #parent_id ~= 16 and tonumber(parent_id, 16) ~= 0 then
    kong.log.warn("invalid jaeger parent ID; ignoring.")
  end

  -- valid span_id is required.
  if #span_id > 16 or tonumber(span_id, 16) == 0 then
    kong.log.warn("invalid jaeger span ID; ignoring.")
    return
  end

  -- valid flags are required
  if #trace_flags ~= 1 and #trace_flags ~= 2 then
    kong.log.warn("invalid jaeger flags; ignoring.")
    return
  end

  -- Jaeger sampled flag: https://www.jaegertracing.io/docs/1.17/client-libraries/#tracespan-identity
  local should_sample = tonumber(trace_flags, 16) % 2 == 1

  trace_id = from_hex(trace_id)
  span_id = from_hex(span_id)
  parent_id = from_hex(parent_id)

  return {
    trace_id      = trace_id,
    span_id       = span_id,
    parent_id     = parent_id,
    reuse_span_id = true,
    should_sample = should_sample,
    baggage       = parse_baggage_headers(headers, JAEGER_BAGGAGE_PATTERN),
  }
end

return JAEGER_EXTRACTOR
