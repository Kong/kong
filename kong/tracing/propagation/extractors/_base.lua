local propagation_utils = require "kong.tracing.propagation.utils"

local to_kong_trace_id = propagation_utils.to_kong_trace_id
local to_kong_span_id  = propagation_utils.to_kong_span_id


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
  return setmetatable(e, _EXTRACTOR)
end


function _EXTRACTOR:verify_any(headers)
  if not self.headers_validate.any or next(self.headers_validate.any) == nil then
    return true
  end

  for _, header in ipairs(self.headers_validate.any) do
    if headers and type(headers) == "table" and headers[header] ~= nil then
      return true
    end
  end

  return false
end


function _EXTRACTOR:verify_all(headers)
  if not self.headers_validate.all or next(self.headers_validate.all) == nil then
    return true
  end

  for _, header in ipairs(self.headers_validate.all) do
    if not headers or type(headers) ~= "table" or headers[header] == nil then
      return false
    end
  end

  return true
end


function _EXTRACTOR:verify_headers(headers)
  return self:verify_any(headers) and
         self:verify_all(headers)
end


function _EXTRACTOR:extract(headers)
  -- check header requirements
  local headers_found = headers and self:verify_headers(headers)

  local ext_tracing_ctx, err
  if headers_found then
    ext_tracing_ctx, err = self:get_context(headers)

    if err then
      return nil, err
    end
  end

  -- update extracted context adding the extracted trace id's original size
  -- this is used by injectors to determine the most appropriate size for the
  -- trace ID in case multiple sizes are allowed (e.g. B3)
  if ext_tracing_ctx and ext_tracing_ctx.trace_id then
    ext_tracing_ctx.trace_id_original_size = #ext_tracing_ctx.trace_id
  end

  -- convert IDs to internal format
  if ext_tracing_ctx then
    ext_tracing_ctx.trace_id  = to_kong_trace_id(ext_tracing_ctx.trace_id)
    ext_tracing_ctx.span_id   = to_kong_span_id(ext_tracing_ctx.span_id)
    ext_tracing_ctx.parent_id = to_kong_span_id(ext_tracing_ctx.parent_id)
  end

  return ext_tracing_ctx
end


--- Extract tracing context from request headers.
--
-- Function to be implemented by Extractor sublcasses, it extracts the tracing
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
--  8. single_header: For extractors that support multiple formats, whether the
--     context was extracted from the single or the multi-header format.
function _EXTRACTOR:get_context(headers)
  return nil, "get_context() not implemented in base class"
end


return _EXTRACTOR
