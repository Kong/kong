local _EXTRACTOR        = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils = require "kong.observability.tracing.propagation.utils"

local type = type
local tonumber = tonumber

local from_hex          = propagation_utils.from_hex
local parse_w3c_baggage = propagation_utils.parse_w3c_baggage

local W3C_TRACECONTEXT_PATTERN = "^(%x+)%-(%x+)%-(%x+)%-(%x+)$"

local MCP_EXTRACTOR = _EXTRACTOR:new({
  name = "mcp",
  headers_validate = {
    any = {},
    all = {},
  }
})

--- Extracts tracing context directly from an MCP _meta table.
--
-- @function extract_from_meta
-- @param table meta The _meta table containing traceparent, tracestate, and/or baggage
-- @return table|nil Extracted tracing context or nil if not found/invalid
local function extract_from_meta(meta)
  if type(meta) ~= "table" then
    return nil
  end

  local traceparent = meta["traceparent"]
  if type(traceparent) ~= "string" or traceparent == "" then
    return nil
  end

  local version, trace_id, parent_id, flags = traceparent:match(W3C_TRACECONTEXT_PATTERN)

  -- values are not parseable hexadecimal and therefore invalid.
  if version == nil or trace_id == nil or parent_id == nil or flags == nil then
    kong.log.warn("invalid MCP traceparent; ignoring.")
    return nil
  end

  -- Only support version 00 of the W3C Trace Context spec.
  if version ~= "00" then
    kong.log.warn("invalid MCP Trace Context version; ignoring.")
    return nil
  end

  -- valid trace_id is required (32 hex characters, non-zero)
  if #trace_id ~= 32 or tonumber(trace_id, 16) == 0 then
    kong.log.warn("invalid MCP trace context trace ID; ignoring.")
    return nil
  end

  -- valid parent_id is required (16 hex characters, non-zero)
  if #parent_id ~= 16 or tonumber(parent_id, 16) == 0 then
    kong.log.warn("invalid MCP trace context parent ID; ignoring.")
    return nil
  end

  -- valid flags are required (2 hex characters)
  if #flags ~= 2 then
    kong.log.warn("invalid MCP trace context flags; ignoring.")
    return nil
  end

  local flags_number = tonumber(flags, 16)
  -- W3C sampled flag: https://www.w3.org/TR/trace-context/#sampled-flag
  local should_sample = flags_number % 2 == 1

  trace_id  = from_hex(trace_id)
  parent_id = from_hex(parent_id)

  local tracestate = meta["tracestate"]
  if type(tracestate) ~= "string" or tracestate == "" then
    tracestate = nil
  end

  local baggage = parse_w3c_baggage(meta["baggage"])

  return {
    trace_id      = trace_id,
    span_id       = parent_id,
    parent_id     = nil,
    should_sample = should_sample,
    baggage       = baggage,
    tracestate    = tracestate,
    w3c_flags     = flags_number,
  }
end

--- Locates the _meta table from a JSON-RPC request body.
-- Supports:
-- 1. request.params._meta (standard MCP client request)
-- 2. request._meta (root-level meta)
-- 3. Batch request array: request[1].params._meta or request[1]._meta
--
-- @function find_meta_in_body
-- @param table body Decoded JSON-RPC body
-- @return table|nil The discovered _meta table
local function find_meta_in_body(body)
  if type(body) ~= "table" then
    return nil
  end

  -- Batch request: inspect first entry
  if body[1] and type(body[1]) == "table" then
    return find_meta_in_body(body[1])
  end

  if type(body.params) == "table" and type(body.params._meta) == "table" then
    return body.params._meta
  end

  if type(body._meta) == "table" then
    return body._meta
  end

  return nil
end

--- Extracts tracing context from a decoded JSON-RPC body.
--
-- @function extract_from_body
-- @param table body Decoded JSON-RPC request body
-- @return table|nil Extracted tracing context
local function extract_from_body(body)
  local meta = find_meta_in_body(body)
  if meta then
    return extract_from_meta(meta)
  end
  return nil
end

function MCP_EXTRACTOR:get_context(carrier)
  if type(carrier) ~= "table" then
    return nil
  end

  -- 1. Direct traceparent in carrier (carrier is the _meta table itself)
  if carrier["traceparent"] ~= nil then
    return extract_from_meta(carrier)
  end

  -- 2. Direct _meta in carrier
  if type(carrier["_meta"]) == "table" then
    return extract_from_meta(carrier["_meta"])
  end

  -- 3. Carrier is a parsed JSON-RPC request body
  local ctx_from_body = extract_from_body(carrier)
  if ctx_from_body then
    return ctx_from_body
  end

  -- 4. If running in live request context and carrier has no meta,
  -- attempt to read the request body if available
  if kong and kong.request and type(kong.request.get_body) == "function" then
    local body, err = kong.request.get_body()
    if not err and type(body) == "table" then
      return extract_from_body(body)
    end
  end

  return nil
end

MCP_EXTRACTOR.extract_from_meta = extract_from_meta
MCP_EXTRACTOR.extract_from_body = extract_from_body

return MCP_EXTRACTOR
