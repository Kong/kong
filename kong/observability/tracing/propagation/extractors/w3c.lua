local _EXTRACTOR               = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils        = require "kong.observability.tracing.propagation.utils"

local type = type
local tonumber = tonumber

local from_hex                 = propagation_utils.from_hex

local W3C_TRACECONTEXT_PATTERN = "^(%x+)%-(%x+)%-(%x+)%-(%x+)$"

local W3C_EXTRACTOR            = _EXTRACTOR:new({
  headers_validate = {
    any = { "traceparent" }
  }
})


function W3C_EXTRACTOR:get_context(headers)
  local traceparent = headers["traceparent"]
  if type(traceparent) ~= "string" or traceparent == "" then
    return
  end

  local version, trace_id, parent_id, flags = traceparent:match(W3C_TRACECONTEXT_PATTERN)

  -- values are not parseable hexadecimal and therefore invalid.
  if version == nil or trace_id == nil or parent_id == nil or flags == nil then
    kong.log.warn("invalid W3C traceparent header; ignoring.")
    return
  end

  -- Only support version 00 of the W3C Trace Context spec.
  if version ~= "00" then
    kong.log.warn("invalid W3C Trace Context version; ignoring.")
    return
  end

  -- valid trace_id is required.
  if #trace_id ~= 32 or tonumber(trace_id, 16) == 0 then
    kong.log.warn("invalid W3C trace context trace ID; ignoring.")
    return
  end

  -- valid parent_id is required.
  if #parent_id ~= 16 or tonumber(parent_id, 16) == 0 then
    kong.log.warn("invalid W3C trace context parent ID; ignoring.")
    return
  end

  -- valid flags are required
  if #flags ~= 2 then
    kong.log.warn("invalid W3C trace context flags; ignoring.")
    return
  end

  local flags_number = tonumber(flags, 16)
  -- W3C sampled flag: https://www.w3.org/TR/trace-context/#sampled-flag
  local should_sample = flags_number % 2 == 1

  trace_id            = from_hex(trace_id)
  parent_id           = from_hex(parent_id)

  return {
    trace_id      = trace_id,
    -- in w3c "parent" is "ID of this request as known by the caller"
    -- i.e. the parent span of the receiver. (https://www.w3.org/TR/trace-context/#parent-id)
    -- Internally we call that "span_id"
    span_id       = parent_id,
    parent_id     = nil,
    should_sample = should_sample,
    baggage       = nil,
    w3c_flags     = flags_number,
  }
end

return W3C_EXTRACTOR
