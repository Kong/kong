local propagation_utils = require "kong.observability.tracing.propagation.utils"

local ipairs = ipairs
local type = type

local to_kong_trace_id  = propagation_utils.to_kong_trace_id
local to_kong_span_id   = propagation_utils.to_kong_span_id


local _EXTRACTOR = {
  name = "base_extractor",
  headers_validate = {
    any = {},
    all = {},
  },
}
_EXTRACTOR.__index = _EXTRACTOR


--- Instantiate a new extractor.
--
-- Constructor to create a new extractor instance. It accepts a name (might be
-- used in the future for logging purposes) and a `headers_validate` table that
-- specifies the extractor's header requirements.
--
-- @function _EXTRACTOR:new
-- @param table e Extractor instance to use for creating the new object
--   the table can have the following fields:
--   * `name` (string, optional): the name of the extractor, currently not used,
--      might be used in the future for logging from this class.
--   * `headers_validate` (table, optional): a table with the following fields:
--     * `any` (table, optional): a list of headers that are required to be
--       present in the request. If any of the headers is present, the extractor
--       will be considered valid.
--     * `all` (table, optional): a list of headers that are required to be
--       present in the request. All headers must be present for the extractor
--       to be considered valid.
--
-- @usage
-- local my_extractor = _EXTRACTOR:new("my_extractor", {
--   headers_validate = {
--     all = { "Some-Required-Header" },
--     any = { "Semi", "Optional", "Headers" }
--   }
-- })
function _EXTRACTOR:new(e)
  e = e or {}
  local inst = setmetatable(e, _EXTRACTOR)

  local err = "invalid extractor instance: "
  assert(type(inst.headers_validate) == "table",
         err .. "invalid headers_validate variable")

  return inst
end


function _EXTRACTOR:verify_any(headers)
  local any = self.headers_validate.any
  if not any or #any == 0 then
    return true
  end

  if not headers or type(headers) ~= "table" then
    return false
  end

  for _, header in ipairs(any) do
    if headers[header] ~= nil then
      return true
    end
  end

  return false
end


function _EXTRACTOR:verify_all(headers)
  local all = self.headers_validate.all
  if not all or #all == 0 then
    return true
  end

  if not headers or type(headers) ~= "table" then
    return false
  end

  for _, header in ipairs(all) do
    if headers[header] == nil then
      return false
    end
  end

  return true
end


-- extractors fail silently if tracing headers are just missing from the
-- request, which is a valid scenario.
function _EXTRACTOR:verify_headers(headers)
  return self:verify_any(headers) and
         self:verify_all(headers)
end


--- Extract tracing context from request headers.
--
-- Function to call the extractor instance's get_context function
-- and format the tracing context to match Kong's internal interface.
--
-- @function_EXTRACTOR:extract(headers)
-- @param table headers The request headers
-- @return table|nil Extracted tracing context as described in get_context
-- returning nil (and silently failing) is valid to indicate the extractor
-- failed to fetch any tracing context from the request headers, which is
-- a valid scenario.
function _EXTRACTOR:extract(headers)
  local headers_verified = self:verify_headers(headers)
  if not headers_verified then
    return
  end

  local ext_tracing_ctx, ext_err = self:get_context(headers)
  if ext_err then
    -- extractors should never return errors, they should fail silently
    -- even when ext_tracing_ctx is nil or empty.
    -- Only the base extractor returns a "not implemented method" error message
    kong.log.err("failed to extract tracing context: ", ext_err)
  end

  if not ext_tracing_ctx then
    return
  end

  -- update extracted context adding the extracted trace id's original size
  -- this is used by injectors to determine the most appropriate size for the
  -- trace ID in case multiple sizes are allowed (e.g. B3, ot)
  if ext_tracing_ctx.trace_id then
    ext_tracing_ctx.trace_id_original_size = #ext_tracing_ctx.trace_id
  end

  -- convert IDs to internal format
  ext_tracing_ctx.trace_id  = to_kong_trace_id(ext_tracing_ctx.trace_id)
  ext_tracing_ctx.span_id   = to_kong_span_id(ext_tracing_ctx.span_id)
  ext_tracing_ctx.parent_id = to_kong_span_id(ext_tracing_ctx.parent_id)

  return ext_tracing_ctx
end


--- Obtain tracing context from request headers.
--
-- Function to be implemented by Extractor subclasses, it extracts the tracing
-- context from request headers.
--
-- @function _EXTRACTOR:get_context(headers)
-- @param table headers The request headers
-- @return table|nil Extracted tracing context.
--  This is a table with the following structure:
--  {
--    trace_id          = {encoded_string | nil},
--    span_id           = {encoded_string | nil},
--    parent_id         = {encoded_string | nil},
--    reuse_span_id     = {boolean        | nil},
--    should_sample     = {boolean        | nil},
--    baggage           = {table          | nil},
--    flags             = {string         | nil},
--    w3c_flags         = {string         | nil},
--    single_header     = {boolean        | nil},
--  }
--
--  1. trace_id: The trace ID extracted from the incoming tracing headers.
--  2. span_id: The span_id field can have different meanings depending on the
--     format:
--      * Formats that support reusing span ID on both sides of the request
--        and provide two span IDs (span, parent): span ID is the ID of the
--        sender-receiver span.
--      * Formats that provide only one span ID (sometimes called parent_id):
--        span ID is the ID of the sender's span.
--  3. parent_id: Only used to identify the parent of the span for formats
--     that support reusing span IDs on both sides of the request.
--     Plugins can ignore this field if they do not support this feature
--     (like OTel does) and use span_id as the parent of the span instead.
--  4. reuse_span_id: Whether the format the ctx was extracted from supports
--     reusing span_ids on both sides of the request.
--  5. should_sample: Whether the trace should be sampled or not.
--  6. baggage: A table with the baggage items extracted from the incoming
--     tracing headers.
--  7. flags: Flags extracted from the incoming tracing headers (B3)
--  7. w3c_flags: Flags extracted from the incoming tracing headers (W3C)
--  8. single_header: For extractors that support multiple formats, whether the
--     context was extracted from the single or the multi-header format.
function _EXTRACTOR:get_context(headers)
  return nil, "get_context() not implemented in base class"
end


return _EXTRACTOR
