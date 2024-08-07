local _EXTRACTOR               = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils        = require "kong.observability.tracing.propagation.utils"

local from_hex                 = propagation_utils.from_hex
local parse_baggage_headers    = propagation_utils.parse_baggage_headers

local OT_BAGGAGE_PATTERN = "^ot%-baggage%-(.*)$"

local OT_EXTRACTOR = _EXTRACTOR:new({
  headers_validate = {
    any = {
      "ot-tracer-sampled",
      "ot-tracer-traceid",
      "ot-tracer-spanid",
    },
  }
})


function OT_EXTRACTOR:get_context(headers)
  local should_sample = headers["ot-tracer-sampled"]
  if should_sample == "1" or should_sample == "true" then
    should_sample = true
  elseif should_sample == "0" or should_sample == "false" then
    should_sample = false
  elseif should_sample ~= nil then
    kong.log.warn("ot-tracer-sampled header invalid; ignoring.")
    should_sample = nil
  end

  local trace_id, span_id
  local invalid_id = false

  local trace_id_header = headers["ot-tracer-traceid"]
  if trace_id_header and ((#trace_id_header ~= 16 and #trace_id_header ~= 32) or trace_id_header:match("%X")) then
    kong.log.warn("ot-tracer-traceid header invalid; ignoring.")
    invalid_id = true
  else
    trace_id = trace_id_header
  end

  local span_id_header = headers["ot-tracer-spanid"]
  if span_id_header and (#span_id_header ~= 16 or span_id_header:match("%X")) then
    kong.log.warn("ot-tracer-spanid header invalid; ignoring.")
    invalid_id = true
  else
    span_id = span_id_header
  end

  if trace_id == nil or invalid_id then
    trace_id = nil
    span_id = nil
  end

  trace_id = trace_id and from_hex(trace_id) or nil
  span_id = span_id and from_hex(span_id) or nil


  return {
    trace_id      = trace_id,
    span_id       = span_id,
    parent_id     = nil,
    should_sample = should_sample,
    baggage       = parse_baggage_headers(headers, OT_BAGGAGE_PATTERN),
  }
end

return OT_EXTRACTOR
