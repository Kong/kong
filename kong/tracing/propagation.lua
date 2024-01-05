local to_hex = require "resty.string".to_hex
local openssl_bignum = require "resty.openssl.bn"
local table_merge = require "kong.tools.utils".table_merge
local split = require "kong.tools.utils".split
local strip = require "kong.tools.utils".strip
local tracing_context = require "kong.tracing.tracing_context"
local unescape_uri = ngx.unescape_uri
local char = string.char
local match = string.match
local sub = string.sub
local gsub = string.gsub
local fmt = string.format
local concat = table.concat
local ipairs = ipairs
local to_ot_trace_id


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
local W3C_TRACEID_LEN = 16

local AWS_KV_PAIR_DELIM = ";"
local AWS_KV_DELIM = "="
local AWS_TRACE_ID_KEY = "Root"
local AWS_TRACE_ID_LEN = 35
local AWS_TRACE_ID_PATTERN = "^(%x+)%-(%x+)%-(%x+)$"
local AWS_TRACE_ID_VERSION = "1"
local AWS_TRACE_ID_TIMESTAMP_LEN = 8
local AWS_TRACE_ID_UNIQUE_ID_LEN = 24
local AWS_PARENT_ID_KEY = "Parent"
local AWS_PARENT_ID_LEN = 16
local AWS_SAMPLED_FLAG_KEY = "Sampled"

local GCP_TRACECONTEXT_REGEX = "^(?<trace_id>[0-9a-f]{32})/(?<span_id>[0-9]{1,20})(;o=(?<trace_flags>[0-9]))?$"
local GCP_TRACE_ID_LEN = 32

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


local function to_w3c_trace_id(trace_id)
  if #trace_id < W3C_TRACEID_LEN then
    return ('\0'):rep(W3C_TRACEID_LEN - #trace_id) .. trace_id
  elseif #trace_id > W3C_TRACEID_LEN then
    return trace_id:sub(-W3C_TRACEID_LEN)
  end

  return trace_id
end

local function to_gcp_trace_id(trace_id)
  if #trace_id < GCP_TRACE_ID_LEN then
    return ('0'):rep(GCP_TRACE_ID_LEN - #trace_id) .. trace_id
  elseif #trace_id > GCP_TRACE_ID_LEN then
    return trace_id:sub(-GCP_TRACE_ID_LEN)
  end

  return trace_id
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

local function parse_aws_headers(aws_header)
  -- allow testing to spy on this.
  local warn = kong.log.warn

  if type(aws_header) ~= "string" then
    return nil, nil, nil
  end

  local trace_id = nil
  local span_id = nil
  local should_sample = nil

  -- The AWS trace header consists of multiple `key=value` separated by a delimiter `;`
  -- We can retrieve the trace id with the `Root` key, the span id with the `Parent`
  -- key and the sampling parameter with the `Sampled` flag. Extra information should be ignored.
  --
  -- The trace id has a custom format: `version-timestamp-uniqueid` and an opentelemetry compatible
  -- id can be deduced by concatenating the timestamp and uniqueid.
  --
  -- https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html#xray-concepts-tracingheader
  for _, key_pair in ipairs(split(aws_header, AWS_KV_PAIR_DELIM)) do
    local key_pair_list = split(key_pair, AWS_KV_DELIM)
    local key = strip(key_pair_list[1])
    local value = strip(key_pair_list[2])

    if key == AWS_TRACE_ID_KEY then
      local version, timestamp_subset, unique_id_subset = match(value, AWS_TRACE_ID_PATTERN)

      if #value ~= AWS_TRACE_ID_LEN or version ~= AWS_TRACE_ID_VERSION
      or #timestamp_subset ~= AWS_TRACE_ID_TIMESTAMP_LEN
      or #unique_id_subset ~= AWS_TRACE_ID_UNIQUE_ID_LEN then
        warn("invalid aws header trace id; ignoring.")
        return nil, nil, nil
      end

      trace_id = from_hex(timestamp_subset .. unique_id_subset)
    elseif key == AWS_PARENT_ID_KEY then
      if #value ~= AWS_PARENT_ID_LEN then
        warn("invalid aws header parent id; ignoring.")
        return nil, nil, nil
      end
      span_id = from_hex(value)
    elseif key == AWS_SAMPLED_FLAG_KEY then
      if value ~= "0" and value ~= "1" then
        warn("invalid aws header sampled flag; ignoring.")
        return nil, nil, nil
      end
      should_sample = value == "1"
    end
  end
  return trace_id, span_id, should_sample
end

local function parse_gcp_headers(gcp_header)
  local warn = kong.log.warn

  if type(gcp_header) ~= "string" then
    return nil, nil, nil
  end

  local match, err = ngx.re.match(gcp_header, GCP_TRACECONTEXT_REGEX, 'jo')
  if not match then
    local warning = "invalid GCP header"
    if err then
      warning = warning .. ": " .. err
    end

    warn(warning .. "; ignoring.")

    return nil, nil, nil
  end

  local trace_id = from_hex(match["trace_id"])
  local span_id = openssl_bignum.from_dec(match["span_id"]):to_binary()
  local should_sample = match["trace_flags"] == "1"

  return trace_id, span_id, should_sample 
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

  local aws_header = headers["x-amzn-trace-id"]
  if aws_header then
    return "aws", aws_header
  end

  local gcp_header = headers["x-cloud-trace-context"]
  if gcp_header then
    return "gcp", gcp_header
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
  elseif header_type == "aws" then
    trace_id, span_id, should_sample = parse_aws_headers(composed_header)
  elseif header_type == "gcp" then
    trace_id, span_id, should_sample = parse_gcp_headers(composed_header)
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


-- set outgoing propagation headers
--
-- @tparam string conf_header_type type of tracing header to use
-- @tparam string found_header_type type of tracing header found in request
-- @tparam table proxy_span span to be propagated
-- @tparam string conf_default_header_type used when conf_header_type=ignore
local function set(conf_header_type, found_header_type, proxy_span, conf_default_header_type)
  -- proxy_span can be noop, in which case it should not be propagated.
  if proxy_span.is_recording == false then
    kong.log.debug("skipping propagation of noop span")
    return
  end

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

  -- contains all the different formats of the current trace ID, with zero or
  -- more of the following entries:
  -- {
  --   ["b3"] = "<b3_trace_id>", -- the trace_id when the request has a b3 or X-B3-TraceId (zipkin) header
  --   ["w3c"] = "<w3c_trace_id>", -- the trace_id when the request has a W3C header
  --   ["jaeger"] = "<jaeger_trace_id>", -- the trace_id when the request has a jaeger tracing header
  --   ["ot"] = "<ot_trace_id>", -- the trace_id when the request has an OpenTelemetry tracing header
  --   ["aws"] = "<aws_trace_id>", -- the trace_id when the request has an aws tracing header
  --   ["gcp"] = "<gcp_trace_id>", -- the trace_id when the request has a gcp tracing header
  -- }
  local trace_id_formats = {}

  if conf_header_type == "b3" or found_header_type == "b3"
  then
    local trace_id = to_hex(proxy_span.trace_id)
    trace_id_formats.b3 = trace_id

    set_header("x-b3-traceid", trace_id)
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
    local trace_id = to_hex(proxy_span.trace_id)
    trace_id_formats.b3 = trace_id

    set_header("b3", trace_id ..
        "-" .. to_hex(proxy_span.span_id) ..
        "-" .. (proxy_span.should_sample and "1" or "0") ..
        (proxy_span.parent_id and "-" .. to_hex(proxy_span.parent_id) or ""))
  end

  if conf_header_type == "w3c" or found_header_type == "w3c" then
    -- OTEL uses w3c trace context format so to_ot_trace_id works here
    local trace_id = to_hex(to_w3c_trace_id(proxy_span.trace_id))
    trace_id_formats.w3c = trace_id

    set_header("traceparent", fmt("00-%s-%s-%s",
        trace_id,
        to_hex(proxy_span.span_id),
        proxy_span.should_sample and "01" or "00"))
  end

  if conf_header_type == "jaeger" or found_header_type == "jaeger" then
    local trace_id = to_hex(proxy_span.trace_id)
    trace_id_formats.jaeger = trace_id

    set_header("uber-trace-id", fmt("%s:%s:%s:%s",
        trace_id,
        to_hex(proxy_span.span_id),
        proxy_span.parent_id and to_hex(proxy_span.parent_id) or "0",
      proxy_span.should_sample and "01" or "00"))
  end

  if conf_header_type == "ot" or found_header_type == "ot" then
    to_ot_trace_id = to_ot_trace_id or require "kong.plugins.opentelemetry.otlp".to_ot_trace_id
    local trace_id = to_hex(to_ot_trace_id(proxy_span.trace_id))
    trace_id_formats.ot = trace_id

    set_header("ot-tracer-traceid", trace_id)
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

  if conf_header_type == "aws" or found_header_type == "aws" then
    local trace_id = to_hex(proxy_span.trace_id)
    trace_id_formats.aws = trace_id

    set_header("x-amzn-trace-id", "Root=" .. AWS_TRACE_ID_VERSION .. "-" ..
        sub(trace_id, 1, AWS_TRACE_ID_TIMESTAMP_LEN) .. "-" ..
        sub(trace_id, AWS_TRACE_ID_TIMESTAMP_LEN + 1, #trace_id) ..
        ";Parent=" .. to_hex(proxy_span.span_id) .. ";Sampled=" ..
        (proxy_span.should_sample and "1" or "0")
    )
  end

  if conf_header_type == "gcp" or found_header_type == "gcp" then
    local trace_id = to_gcp_trace_id(to_hex(proxy_span.trace_id))
    trace_id_formats.gcp = trace_id

    set_header("x-cloud-trace-context", trace_id ..
      "/" .. openssl_bignum.from_binary(proxy_span.span_id):to_dec() .. 
      ";o=" .. (proxy_span.should_sample and "1" or "0")
    )
  end

  trace_id_formats = tracing_context.add_trace_id_formats(trace_id_formats)
  -- add trace IDs to log serializer output
  kong.log.set_serialize_value("trace_id", trace_id_formats)
end


return {
  parse = parse,
  set = set,
  from_hex = from_hex,
}
