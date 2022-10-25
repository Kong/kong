local to_hex = require "resty.string".to_hex
local table_merge = require "kong.tools.utils".table_merge
local unescape_uri = ngx.unescape_uri
local char = string.char
local match = string.match
local gsub = string.gsub
local fmt = string.format
local concat = table.concat


local baggage_mt = {
  __newindex = function()
    error("attempt to set immutable baggage", 2)
  end,
}

local B3_SINGLE_PATTERN =
  "^(%x+)%-(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)%-?([01d]?)%-?(%x*)$"
local W3C_TRACECONTEXT_PATTERN = "^(%x+)%-(%x+)%-(%x+)%-(%x+)$"
local JAEGER_TRACECONTEXT_PATTERN = "^(%x+):(%x+):(%x+):(%x+)$"
local JAEGER_BAGGAGE_PATTERN = "^uberctx%-(.*)$"
local OT_BAGGAGE_PATTERN = "^ot%-baggage%-(.*)$"

local function hex_to_char(c)
  return char(tonumber(c, 16))
end


local function from_hex(str)
  if str ~= nil then -- allow nil to pass through
    str = gsub(str, "%x%x", hex_to_char)
  end
  return str
end

-- adds `count` number of zeros to the left of the str
local function left_pad_zero(str, count)
  return ('0'):rep(count-#str) .. str
end

local function parse_baggage_headers(headers, header_pattern)
  -- account for both ot and uber baggage headers
  local baggage
  for k, v in pairs(headers) do
    local baggage_key = match(k, header_pattern)
    if baggage_key then
      if baggage then
        baggage[baggage_key] = unescape_uri(v)
      else
        baggage = { [baggage_key] = unescape_uri(v) }
      end
    end
  end

  if baggage then
    return setmetatable(baggage, baggage_mt)
  end
end


local function parse_zipkin_b3_headers(headers, b3_single_header)
  local warn = kong.log.warn

  -- X-B3-Sampled: if an upstream decided to sample this request, we do too.
  local should_sample = headers["x-b3-sampled"]
  if should_sample == "1" or should_sample == "true" then
    should_sample = true
  elseif should_sample == "0" or should_sample == "false" then
    should_sample = false
  elseif should_sample ~= nil then
    warn("x-b3-sampled header invalid; ignoring.")
    should_sample = nil
  end

  -- X-B3-Flags: if it equals '1' then it overrides sampling policy
  -- We still want to warn on invalid sample header, so do this after the above
  local debug_header = headers["x-b3-flags"]
  if debug_header == "1" then
    should_sample = true
  elseif debug_header ~= nil then
    warn("x-b3-flags header invalid; ignoring.")
  end

  local trace_id, span_id, sampled, parent_id
  local had_invalid_id = false

  -- B3 single header
  -- * For speed, the "-" separators between sampled and parent_id are optional on this implementation
  --   This is not guaranteed to happen in future versions and won't be considered a breaking change
  -- * The "sampled" section activates sampling with both "1" and "d". This is to match the
  --   behavior of the X-B3-Flags header
  if b3_single_header and type(b3_single_header) == "string" then
    if b3_single_header == "1" or b3_single_header == "d" then
      should_sample = true

    elseif b3_single_header == "0" then
      should_sample = should_sample or false

    else
      trace_id, span_id, sampled, parent_id =
        match(b3_single_header, B3_SINGLE_PATTERN)

      local trace_id_len = trace_id and #trace_id or 0
      if trace_id
      and (trace_id_len == 16 or trace_id_len == 32)
      and (parent_id == "" or #parent_id == 16)
      then

        if should_sample or sampled == "1" or sampled == "d" then
          should_sample = true
        elseif sampled == "0" then
          should_sample = false
        end

        if parent_id == "" then
          parent_id = nil
        end

      else
        warn("b3 single header invalid; ignoring.")
        had_invalid_id = true
      end
    end
  end

  local trace_id_header = headers["x-b3-traceid"]
  if trace_id_header and ((#trace_id_header ~= 16 and #trace_id_header ~= 32)
                           or trace_id_header:match("%X")) then
    warn("x-b3-traceid header invalid; ignoring.")
    had_invalid_id = true
  else
    trace_id = trace_id or trace_id_header -- b3 single header overrides x-b3-traceid
  end

  local span_id_header = headers["x-b3-spanid"]
  if span_id_header and (#span_id_header ~= 16 or span_id_header:match("%X")) then
    warn("x-b3-spanid header invalid; ignoring.")
    had_invalid_id = true
  else
    span_id = span_id or span_id_header -- b3 single header overrides x-b3-spanid
  end

  local parent_id_header = headers["x-b3-parentspanid"]
  if parent_id_header and (#parent_id_header ~= 16 or parent_id_header:match("%X")) then
    warn("x-b3-parentspanid header invalid; ignoring.")
    had_invalid_id = true
  else
    parent_id = parent_id or parent_id_header -- b3 single header overrides x-b3-parentid
  end

  if trace_id == nil or had_invalid_id then
    return nil, nil, nil, should_sample
  end

  trace_id = from_hex(trace_id)
  span_id = from_hex(span_id)
  parent_id = from_hex(parent_id)

  return trace_id, span_id, parent_id, should_sample
end


local function parse_w3c_trace_context_headers(w3c_header)
  -- allow testing to spy on this.
  local warn = kong.log.warn

  local should_sample = false

  if type(w3c_header) ~= "string" then
    return nil, nil, should_sample
  end

  local version, trace_id, parent_id, trace_flags = match(w3c_header, W3C_TRACECONTEXT_PATTERN)

  -- values are not parseable hexadecimal and therefore invalid.
  if version == nil or trace_id == nil or parent_id == nil or trace_flags == nil then
    warn("invalid W3C traceparent header; ignoring.")
    return nil, nil, nil
  end

  -- Only support version 00 of the W3C Trace Context spec.
  if version ~= "00" then
    warn("invalid W3C Trace Context version; ignoring.")
    return nil, nil, nil
  end

  -- valid trace_id is required.
  if #trace_id ~= 32 or tonumber(trace_id, 16) == 0 then
    warn("invalid W3C trace context trace ID; ignoring.")
    return nil, nil, nil
  end

  -- valid parent_id is required.
  if #parent_id ~= 16 or tonumber(parent_id, 16) == 0 then
    warn("invalid W3C trace context parent ID; ignoring.")
    return nil, nil, nil
  end

  -- valid flags are required
  if #trace_flags ~= 2 then
    warn("invalid W3C trace context flags; ignoring.")
    return nil, nil, nil
  end

  -- W3C sampled flag: https://www.w3.org/TR/trace-context/#sampled-flag
  should_sample = tonumber(trace_flags, 16) % 2 == 1

  trace_id = from_hex(trace_id)
  parent_id = from_hex(parent_id)

  return trace_id, parent_id, should_sample
end

local function parse_ot_headers(headers)
  local warn = kong.log.warn

  local should_sample = headers["ot-tracer-sampled"]
  if should_sample == "1" or should_sample == "true" then
    should_sample = true
  elseif should_sample == "0" or should_sample == "false" then
    should_sample = false
  elseif should_sample ~= nil then
    warn("ot-tracer-sampled header invalid; ignoring.")
    should_sample = nil
  end

  local trace_id, span_id
  local had_invalid_id = false

  local trace_id_header = headers["ot-tracer-traceid"]
  if trace_id_header and ((#trace_id_header ~= 16 and #trace_id_header ~= 32) or trace_id_header:match("%X")) then
    warn("ot-tracer-traceid header invalid; ignoring.")
    had_invalid_id = true
  else
    trace_id = trace_id_header
  end

  local span_id_header = headers["ot-tracer-spanid"]
  if span_id_header and (#span_id_header ~= 16 or span_id_header:match("%X")) then
    warn("ot-tracer-spanid header invalid; ignoring.")
    had_invalid_id = true
  else
    span_id = span_id_header
  end

  if trace_id == nil or had_invalid_id then
    return nil, nil, should_sample
  end

  trace_id = from_hex(trace_id)
  span_id = from_hex(span_id)

  return trace_id, span_id, should_sample
end


local function parse_jaeger_trace_context_headers(jaeger_header)
  -- allow testing to spy on this.
  local warn = kong.log.warn

  if type(jaeger_header) ~= "string" then
    return nil, nil, nil, nil
  end

  local trace_id, span_id, parent_id, trace_flags = match(jaeger_header, JAEGER_TRACECONTEXT_PATTERN)

  -- values are not parsable hexidecimal and therefore invalid.
  if trace_id == nil or span_id == nil or parent_id == nil or trace_flags == nil then
    warn("invalid jaeger uber-trace-id header; ignoring.")
    return nil, nil, nil, nil
  end

  -- valid trace_id is required.
  if #trace_id > 32 or tonumber(trace_id, 16) == 0 then
    warn("invalid jaeger trace ID; ignoring.")
    return nil, nil, nil, nil
  end

  -- if trace_id is not of length 32 chars then 0-pad to left
  if #trace_id < 32 then
    trace_id = left_pad_zero(trace_id, 32)
  end

  -- validating parent_id. If it is invalid just logging, as it can be ignored
  -- https://www.jaegertracing.io/docs/1.29/client-libraries/#tracespan-identity
  if #parent_id ~= 16 and tonumber(parent_id, 16) ~= 0 then
    warn("invalid jaeger parent ID; ignoring.")
  end

  -- valid span_id is required.
  if #span_id > 16 or tonumber(span_id, 16) == 0 then
    warn("invalid jaeger span ID; ignoring.")
    return nil, nil, nil, nil
  end

  -- if span id length is less than 16 then 0-pad left
  if #span_id < 16 then
    span_id = left_pad_zero(span_id, 16)
  end

  -- valid flags are required
  if #trace_flags ~= 1 and #trace_flags ~= 2 then
    warn("invalid jaeger flags; ignoring.")
    return nil, nil, nil, nil
  end

  -- Jaeger sampled flag: https://www.jaegertracing.io/docs/1.17/client-libraries/#tracespan-identity
  local should_sample = tonumber(trace_flags, 16) % 2 == 1

  trace_id = from_hex(trace_id)
  span_id = from_hex(span_id)
  parent_id = from_hex(parent_id)

  return trace_id, span_id, parent_id, should_sample
end


-- This plugin understands several tracing header types:
-- * Zipkin B3 headers (X-B3-TraceId, X-B3-SpanId, X-B3-ParentId, X-B3-Sampled, X-B3-Flags)
-- * Zipkin B3 "single header" (a single header called "B3", composed of several fields)
--   * spec: https://github.com/openzipkin/b3-propagation/blob/master/RATIONALE.md#b3-single-header-format
-- * W3C "traceparent" header - also a composed field
--   * spec: https://www.w3.org/TR/trace-context/
-- * Jaeger's uber-trace-id & baggage headers
--   * spec: https://www.jaegertracing.io/docs/1.21/client-libraries/#tracespan-identity
-- * OpenTelemetry ot-tracer-* tracing headers.
--   * OpenTelemetry spec: https://github.com/open-telemetry/opentelemetry-specification
--   * Base implementation followed: https://github.com/open-telemetry/opentelemetry-java/blob/96e8523544f04c305da5382854eee06218599075/extensions/trace_propagators/src/main/java/io/opentelemetry/extensions/trace/propagation/OtTracerPropagator.java
--
-- The plugin expects request to be using *one* of these types. If several of them are
-- encountered on one request, only one kind will be transmitted further. The order is
--
--      B3-single > B3 > W3C > Jaeger > OT
--
-- Exceptions:
--
-- * When both B3 and B3-single fields are present, the B3 fields will be "ammalgamated"
--   into the resulting B3-single field. If they present contradictory information (i.e.
--   different TraceIds) then B3-single will "win".
--
-- * The erroneous formatting on *any* header (even those overridden by B3 single) results
--   in rejection (ignoring) of all headers. This rejection is logged.
local function find_header_type(headers)
  local b3_single_header = headers["b3"]
  if not b3_single_header then
    local tracestate_header = headers["tracestate"]

    -- handling tracestate header if it is multi valued
    if type(tracestate_header) == "table" then
      -- https://www.w3.org/TR/trace-context/#tracestate-header
      -- Handling multi value header : https://httpwg.org/specs/rfc7230.html#field.order
      tracestate_header = concat(tracestate_header, ',')
      kong.log.debug("header `tracestate` is a table :" .. tracestate_header)
    end

    if tracestate_header then
      b3_single_header = match(tracestate_header, "^b3=(.+)$")
    end
  end

  if b3_single_header then
    return "b3-single", b3_single_header
  end

  if headers["x-b3-sampled"]
  or headers["x-b3-flags"]
  or headers["x-b3-traceid"]
  or headers["x-b3-spanid"]
  or headers["x-b3-parentspanid"]
  then
    return "b3"
  end

  local w3c_header = headers["traceparent"]
  if w3c_header then
    return "w3c", w3c_header
  end

  local jaeger_header = headers["uber-trace-id"]
  if jaeger_header then
    return "jaeger", jaeger_header
  end

  local ot_header = headers["ot-tracer-traceid"]
  if ot_header then
    return "ot", ot_header
  end
end


local function parse(headers, conf_header_type)
  if conf_header_type == "ignore" then
    return nil
  end

  -- Check for B3 headers first
  local header_type, composed_header = find_header_type(headers)
  local trace_id, span_id, parent_id, should_sample

  if header_type == "b3" or header_type == "b3-single" then
    trace_id, span_id, parent_id, should_sample = parse_zipkin_b3_headers(headers, composed_header)
  elseif header_type == "w3c" then
    trace_id, parent_id, should_sample = parse_w3c_trace_context_headers(composed_header)
  elseif header_type == "jaeger" then
    trace_id, span_id, parent_id, should_sample = parse_jaeger_trace_context_headers(composed_header)
  elseif header_type == "ot" then
    trace_id, parent_id, should_sample = parse_ot_headers(headers)
  end

  if not trace_id then
    return header_type, trace_id, span_id, parent_id, should_sample
  end

  -- Parse baggage headers
  local baggage
  local ot_baggage = parse_baggage_headers(headers, OT_BAGGAGE_PATTERN)
  local jaeger_baggage = parse_baggage_headers(headers, JAEGER_BAGGAGE_PATTERN)
  if ot_baggage and jaeger_baggage then
    baggage = table_merge(ot_baggage, jaeger_baggage)
  else
    baggage = ot_baggage or jaeger_baggage or nil
  end


  return header_type, trace_id, span_id, parent_id, should_sample, baggage
end


local function set(conf_header_type, found_header_type, proxy_span, conf_default_header_type)
  local set_header = kong.service.request.set_header

  -- If conf_header_type is set to `preserve`, found_header_type is used over default_header_type;
  -- if conf_header_type is set to `ignore`, found_header_type is not set, thus default_header_type is used.
  if conf_header_type ~= "preserve" and
     conf_header_type ~= "ignore" and
     found_header_type ~= nil and
     conf_header_type ~= found_header_type
  then
    kong.log.warn("Mismatched header types. conf: " .. conf_header_type .. ". found: " .. found_header_type)
  end

  found_header_type = found_header_type or conf_default_header_type or "b3"

  if conf_header_type == "b3" or found_header_type == "b3"
  then
    set_header("x-b3-traceid", to_hex(proxy_span.trace_id))
    set_header("x-b3-spanid", to_hex(proxy_span.span_id))
    if proxy_span.parent_id then
      set_header("x-b3-parentspanid", to_hex(proxy_span.parent_id))
    end
    local Flags = kong.request.get_header("x-b3-flags") -- Get from request headers
    if Flags then
      set_header("x-b3-flags", Flags)
    else
      set_header("x-b3-sampled", proxy_span.should_sample and "1" or "0")
    end
  end

  if conf_header_type == "b3-single" or found_header_type == "b3-single" then
    set_header("b3", to_hex(proxy_span.trace_id) ..
        "-" .. to_hex(proxy_span.span_id) ..
        "-" .. (proxy_span.should_sample and "1" or "0") ..
        (proxy_span.parent_id and "-" .. to_hex(proxy_span.parent_id) or ""))
  end

  if conf_header_type == "w3c" or found_header_type == "w3c" then
    set_header("traceparent", fmt("00-%s-%s-%s",
        to_hex(proxy_span.trace_id),
        to_hex(proxy_span.span_id),
      proxy_span.should_sample and "01" or "00"))
  end

  if conf_header_type == "jaeger" or found_header_type == "jaeger" then
    set_header("uber-trace-id", fmt("%s:%s:%s:%s",
        to_hex(proxy_span.trace_id),
        to_hex(proxy_span.span_id),
        proxy_span.parent_id and to_hex(proxy_span.parent_id) or "0",
      proxy_span.should_sample and "01" or "00"))
  end

  if conf_header_type == "ot" or found_header_type == "ot" then
    set_header("ot-tracer-traceid", to_hex(proxy_span.trace_id))
    set_header("ot-tracer-spanid", to_hex(proxy_span.span_id))
    set_header("ot-tracer-sampled", proxy_span.should_sample and "1" or "0")

    for key, value in proxy_span:each_baggage_item() do
      set_header("ot-baggage-"..key, ngx.escape_uri(value))
    end
  end

  for key, value in proxy_span:each_baggage_item() do
    -- XXX: https://github.com/opentracing/specification/issues/117
    set_header("uberctx-"..key, ngx.escape_uri(value))
  end
end


return {
  parse = parse,
  set = set,
  from_hex = from_hex,
}
