local unescape_uri = ngx.unescape_uri
local char = string.char
local match = string.match
local gsub = string.gsub


local baggage_mt = {
  __newindex = function()
    error("attempt to set immutable baggage", 2)
  end,
}

local B3_SINGLE_PATTERN =
  "^(%x+)%-(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)%-?([01d]?)%-?(%x*)$"

local W3C_TRACECONTEXT_PATTERN = "^(%x+)%-(%x+)%-(%x+)%-(%x+)$"

local function hex_to_char(c)
  return char(tonumber(c, 16))
end


local function from_hex(str)
  if str ~= nil then -- allow nil to pass through
    str = gsub(str, "%x%x", hex_to_char)
  end
  return str
end


local function parse_jaeger_baggage_headers(headers)
  local baggage
  for k, v in pairs(headers) do
    local baggage_key = match(k, "^uberctx%-(.*)$")
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


local function parse_zipkin_b3_headers(headers)
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
  -- The docs for this header are located here:
  --   https://github.com/openzipkin/b3-propagation/blob/master/RATIONALE.md#b3-single-header-format
  --
  -- This code makes some assumptions about edge cases not covered on those docs:
  -- * X-B3-Sampled and X-B3-Flags can be used in conjunction with B3 single. This doesn't raise any errors.
  -- * The id headers (X-B3-TraceId, X-B3-SpanId, X-B3-ParentId) can also be used along with B3 but:
  --   * When both the single header an a id header specify an id, the single header "wins" (overrides)
  --   * All provided id headers are parsed (even those overriden by B3 single)
  --   * An erroneous formatting on *any* header (even those overriden by B3 single) results
  --     in rejection (ignoring) of all headers. This rejection is logged.
  -- * The "sampled" section activates sampling with both "1" and "d". This is to match the
  --   behavior of the X-B3-Flags header
  -- * For speed, the "-" separators between sampled and parent_id are optional on this implementation
  --   This is not guaranteed to happen in future versions and won't be considered a breaking change
  local b3_single_header = headers["b3"]
  if not b3_single_header then
    local tracestate_header = headers["tracestate"]
    if tracestate_header then
      b3_single_header = match(tracestate_header, "^b3=(.+)$")
    end
  end

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

local function parse_w3c_trace_context_headers(headers)
  -- allow testing to spy on this.
  local warn = kong.log.warn

  local version, trace_id, parent_id, trace_flags
  local should_sample = false

  local w3c_trace_context_header = headers["traceparent"]

  -- no W3C trace context
  if w3c_trace_context_header == nil or type(w3c_trace_context_header) ~= "string" then
    return nil, nil, nil, should_sample
  end

  version, trace_id, parent_id, trace_flags = match(w3c_trace_context_header, W3C_TRACECONTEXT_PATTERN)

  -- values are not parsable hexidecimal and therefore invalid.
  if version == nil or trace_id == nil or parent_id == nil or trace_flags == nil then
    warn("invalid W3C traceparent header; ignoring.")
  end

  -- Only support version 00 of the W3C Trace Context spec.
  if version ~= "00" then
    warn("invalid W3C Trace Context version; ignoring.")
    return nil, nil, nil, should_sample
  end

  -- valid trace_id is required.
  if #trace_id ~= 32 or tonumber(trace_id, 16) == 0 then
    warn("invalid W3C trace context trace ID; ignoring.")
    return nil, nil, nil, should_sample
  end

  -- valid parent_id is required.
  if #parent_id ~= 16 or tonumber(parent_id, 16) == 0 then
    warn("invalid W3C trace context parent ID; ignoring.")
    return nil, nil, nil, should_sample
  end

  -- valid flags are required
  if #trace_flags ~= 2 then
    warn("invalid W3C trace context flags; ignoring.")
    return nil, nil, nil, should_sample
  end

  -- W3C sampled flag: https://www.w3.org/TR/trace-context/#sampled-flag
  should_sample = tonumber(trace_flags, 16) % 2 == 1

  trace_id = from_hex(trace_id)
  parent_id = from_hex(parent_id)

  return trace_id, parent_id, should_sample

end

local function parse_http_req_headers(headers)
  -- Check for B3 headers first
  local trace_id, span_id, parent_id, should_sample = parse_zipkin_b3_headers(headers)

  -- TODO: Offer the option to configure which headers to use. For now, W3C wins if it's present
  -- Check for W3C headers
  local w3c_trace_id, w3c_parent_id, w3c_should_sample = parse_w3c_trace_context_headers(headers)
  if w3c_trace_id then
    trace_id, span_id, parent_id, should_sample = w3c_trace_id, nil, w3c_parent_id, w3c_should_sample
  end

  if not trace_id then
    return trace_id, span_id, parent_id, should_sample
  end

  local baggage = parse_jaeger_baggage_headers(headers)

  return trace_id, span_id, parent_id, should_sample, baggage
end


return parse_http_req_headers
