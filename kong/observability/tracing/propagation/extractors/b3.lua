local _EXTRACTOR        = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils = require "kong.observability.tracing.propagation.utils"

local from_hex          = propagation_utils.from_hex
local match             = string.match
local type = type

local B3_SINGLE_PATTERN =
"^(%x+)%-(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)%-?([01d]?)%-?(%x*)$"

local B3_EXTRACTOR      = _EXTRACTOR:new({
  headers_validate = {
    any = {
      "b3",
      "tracestate",
      "x-b3-traceid",
      "x-b3-spanid",
      "x-b3-parentspanid",
      "x-b3-sampled",
      "x-b3-flags",
    }
  }
})


local function read_single_header(headers)
  local b3_single_header = headers["b3"]
  if not b3_single_header then
    local tracestate_header = headers["tracestate"]

    -- handling tracestate header if it is multi valued
    if type(tracestate_header) == "table" then
      -- https://www.w3.org/TR/trace-context/#tracestate-header
      -- Handling multi value header : https://httpwg.org/specs/rfc7230.html#field.order
      for _, v in ipairs(tracestate_header) do
        if type(v) == "string" then
          b3_single_header = match(v, "^b3=(.+)$")
          if b3_single_header then
            break
          end
        end
      end

    elseif tracestate_header then
      b3_single_header = match(tracestate_header, "^b3=(.+)$")
    end
  end

  if not b3_single_header or type(b3_single_header) ~= "string" then
    return
  end

  -- B3 single header
  -- * For speed, the "-" separators between sampled and parent_id are optional on this implementation
  --   This is not guaranteed to happen in future versions and won't be considered a breaking change
  -- * The "sampled" section activates sampling with both "1" and "d". This is to match the
  --   behavior of the X-B3-Flags header
  local trace_id, span_id, should_sample, parent_id, flags
  local invalid_id = false

  if b3_single_header == "1" or b3_single_header == "d" then
    should_sample = true
    if b3_single_header == "d" then
      flags = "1"
    end
  elseif b3_single_header == "0" then
    should_sample = false
  else
    local sampled
    trace_id, span_id, sampled, parent_id =
        match(b3_single_header, B3_SINGLE_PATTERN)

    local trace_id_len = trace_id and #trace_id or 0
    if trace_id
        and (trace_id_len == 16 or trace_id_len == 32)
        and (parent_id == "" or #parent_id == 16)
    then
      if sampled == "1" or sampled == "d" then
        should_sample = true
        if sampled == "d" then
          flags = "1"
        end
      elseif sampled == "0" then
        should_sample = false
      end

      if parent_id == "" then
        parent_id = nil
      end
    else
      kong.log.warn("b3 single header invalid; ignoring.")
      invalid_id = true
    end
  end

  return {
    trace_id      = trace_id,
    span_id       = span_id,
    parent_id     = parent_id,
    should_sample = should_sample,
    invalid_id    = invalid_id,
    flags         = flags,
  }
end


local function read_multi_header(headers)
  -- X-B3-Sampled: if an upstream decided to sample this request, we do too.
  local should_sample = headers["x-b3-sampled"]
  if should_sample == "1" or should_sample == "true" then
    should_sample = true
  elseif should_sample == "0" or should_sample == "false" then
    should_sample = false
  elseif should_sample ~= nil then
    kong.log.warn("x-b3-sampled header invalid; ignoring.")
    should_sample = nil
  end

  -- X-B3-Flags: if it equals '1' then it overrides sampling policy
  -- We still want to kong.log.warn on invalid sample header, so do this after the above
  local debug_header = headers["x-b3-flags"]
  if debug_header == "1" then
    should_sample = true
  elseif debug_header ~= nil then
    kong.log.warn("x-b3-flags header invalid; ignoring.")
  end

  local trace_id, span_id, parent_id
  local invalid_id = false
  local trace_id_header = headers["x-b3-traceid"]

  if trace_id_header and ((#trace_id_header ~= 16 and #trace_id_header ~= 32)
        or trace_id_header:match("%X")) then
    kong.log.warn("x-b3-traceid header invalid; ignoring.")
    invalid_id = true
  else
    trace_id = trace_id_header
  end

  local span_id_header = headers["x-b3-spanid"]
  if span_id_header and (#span_id_header ~= 16 or span_id_header:match("%X")) then
    kong.log.warn("x-b3-spanid header invalid; ignoring.")
    invalid_id = true
  else
    span_id = span_id_header
  end

  local parent_id_header = headers["x-b3-parentspanid"]
  if parent_id_header and (#parent_id_header ~= 16 or parent_id_header:match("%X")) then
    kong.log.warn("x-b3-parentspanid header invalid; ignoring.")
    invalid_id = true
  else
    parent_id = parent_id_header
  end

  return {
    trace_id      = trace_id,
    span_id       = span_id,
    parent_id     = parent_id,
    should_sample = should_sample,
    invalid_id    = invalid_id,
    flags         = debug_header,
  }
end


function B3_EXTRACTOR:get_context(headers)

  local trace_id, span_id, parent_id, should_sample, flags, single_header

  local single_header_ctx = read_single_header(headers)
  if single_header_ctx then
    single_header = true
    should_sample = single_header_ctx.should_sample
    flags = single_header_ctx.flags
    if not single_header_ctx.invalid_id then
      trace_id  = single_header_ctx.trace_id
      span_id   = single_header_ctx.span_id
      parent_id = single_header_ctx.parent_id
    end
  end

  local multi_header_ctx = read_multi_header(headers)
  if multi_header_ctx then
    if should_sample == nil then
      should_sample = multi_header_ctx.should_sample
    end
    flags = flags or multi_header_ctx.flags

    if not multi_header_ctx.invalid_id then
      trace_id  = trace_id  or multi_header_ctx.trace_id
      span_id   = span_id   or multi_header_ctx.span_id
      parent_id = parent_id or multi_header_ctx.parent_id
    end
  end

  if trace_id == nil then
    trace_id  = nil
    span_id   = nil
    parent_id = nil
  end

  trace_id  = trace_id  and from_hex(trace_id) or nil
  span_id   = span_id   and from_hex(span_id) or nil
  parent_id = parent_id and from_hex(parent_id) or nil

  return {
    trace_id          = trace_id,
    span_id           = span_id,
    parent_id         = parent_id,
    reuse_span_id     = true,
    should_sample     = should_sample,
    baggage           = nil,
    flags             = flags,
    single_header     = single_header,
  }
end

return B3_EXTRACTOR
