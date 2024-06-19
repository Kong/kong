local propagation_utils = require "kong.observability.tracing.propagation.utils"

local to_id_size  = propagation_utils.to_id_size
local set_header  = kong.service.request.set_header
local contains    = require("kong.tools.table").table_contains
local type = type
local ipairs = ipairs

local _INJECTOR = {
  name = "base_injector",
  context_validate = {
    any = {},
    all = {},
  },
  -- array of allowed trace_id sizes for an injector
  -- the first element is the default size
  trace_id_allowed_sizes = { 16 },
  span_id_size_bytes = 8,
}
_INJECTOR.__index = _INJECTOR


--- Instantiate a new injector.
--
-- Constructor to create a new injector instance. It accepts a name (used for
-- logging purposes), a `context_validate` table that specifies the injector's
-- context requirements and the trace_id_allowed_sizes and span_id_size_bytes
-- params to define the allowed/expected injector's ID sizes.
--
-- @function _INJECTOR:new
-- @param table e Injector instance to use for creating the new object
--   the table can have the following fields:
--   * `name` (string, optional): the name of the extractor, used for logging
--      from this class.
--   * `context_validate` (table, optional): a table with the following fields:
--     * `any` (table, optional): a list of context fields that are required to
--       be passed to the injector. If any of the headers is present, the
--       injector will be considered valid.
--     * `all` (table, optional): a list of context fields that are required to
--       be passed to the injector. All fields must be present for the
--       injector to be considered valid.
--   * `trace_id_allowed_sizes` (table, optional): list of sizes that the
--       injector is allowed to use for the trace ID. The first element is the
--       default size, the other sizes might be used depending on the incoming
--       trace ID size.
--   * `span_id_size_bytes` (number, optional): the size in bytes of the span
--       ID that the injector is expected to use.
--
-- @usage
-- local my_injector = _INJECTOR:new({
--   name = "my_injector",
--   context_validate = {
--     all = { "trace_id", "span_id" },
--     any = { "parent_id", "should_sample" }
--   },
--   trace_id_allowed_sizes = { 8, 16 },
--   span_id_size_bytes = 8,
-- })
function _INJECTOR:new(e)
  e = e or {}
  local inst = setmetatable(e, _INJECTOR)

  local err = "invalid injector instance: "
  assert(type(inst.context_validate) == "table",
         err .. "invalid context_validate variable")

  assert(type(inst.trace_id_allowed_sizes) == "table" and
         #inst.trace_id_allowed_sizes > 0,
         err .. "invalid trace_id_allowed_sizes variable")

  assert(type(inst.span_id_size_bytes) == "number" and
         inst.span_id_size_bytes > 0,
         err .. "invalid span_id_size_bytes variable")

  return inst
end


function _INJECTOR:verify_any(context)
  local any = self.context_validate.any
  if not any or #any == 0 then
    return true
  end

  if not context or type(context) ~= "table" then
    return false, "no context to inject"
  end

  for _, field in ipairs(any) do
    if context[field] ~= nil then
      return true
    end
  end

  return false, "no required field found in context: " ..
                table.concat(any, ", ")
end


function _INJECTOR:verify_all(context)
  local all = self.context_validate.all
  if not all or #all == 0 then
    return true
  end

  if not context or type(context) ~= "table" then
    return false, "no context to inject"
  end

  for _, field in ipairs(all) do
    if context[field] == nil then
      return false, "field " .. field .. " not found in context"
    end
  end

  return true
end


-- injection failures are reported, injectors are not expected to fail because
-- kong should ensure the tracing context is valid
function _INJECTOR:verify_context(context)
  local ok_any, err_any = self:verify_any(context)
  local ok_all, err_all = self:verify_all(context)

  if ok_any and ok_all then
    return true
  end

  local err = err_any or ""
  if err_all then
    err = err .. (err_any and ", " or "") .. err_all
  end

  return false, err
end


function _INJECTOR:inject(inj_tracing_ctx)
  local context_verified, err = self:verify_context(inj_tracing_ctx)
  if not context_verified then
    return nil, self.name ..  " injector context is invalid: " .. err
  end

  -- Convert IDs to be compatible to the injector's format.
  -- Use trace_id_allowed_sizes to try to keep the original (incoming) size
  -- where possible.
  -- Extractors automatically set `trace_id_original_size` during extraction.
  local orig_size = inj_tracing_ctx.trace_id_original_size
  local allowed = self.trace_id_allowed_sizes
  local new_trace_id_size = contains(allowed, orig_size) and orig_size
      or allowed[1]

  inj_tracing_ctx.trace_id  = to_id_size(inj_tracing_ctx.trace_id, new_trace_id_size)
  inj_tracing_ctx.span_id   = to_id_size(inj_tracing_ctx.span_id, self.span_id_size_bytes)
  inj_tracing_ctx.parent_id = to_id_size(inj_tracing_ctx.parent_id, self.span_id_size_bytes)

  local headers, h_err = self:create_headers(inj_tracing_ctx)
  if not headers then
    return nil, h_err
  end

  for h_name, h_value in pairs(headers) do
    set_header(h_name, h_value)
  end

  local formatted_trace_id, t_err = self:get_formatted_trace_id(inj_tracing_ctx.trace_id)
  if not formatted_trace_id then
    return nil, t_err
  end
  return formatted_trace_id
end


--- Create headers to be injected.
--
-- Function to be implemented by Injector subclasses, uses the extracted
-- tracing context to create and return headers for injection.
--
-- @function _INJECTOR:create_headers(tracing_ctx)
-- @param table tracing_ctx The extracted tracing context.
--   The structure of this table is described in the Extractor base class.
-- @return table/array-of-tables that define the headers to be injected
--   example:
--   return {
--     traceparent = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
--   }
function _INJECTOR:create_headers(tracing_ctx)
  return nil, "headers() not implemented in base class"
end


--- Get the formatted trace ID for the current Injector.
--
-- Function to be implemented by Injector subclasses, it returns a
-- representation of the trace ID, formatted according to the current
-- injector's standard.
--
-- @function _INJECTOR:get_formatted_trace_id(trace_id)
-- @param string trace_id The encoded trace ID.
-- @return table that defines a name and value for the formatted trace ID.
--   This is automatically included in Kong's serialized logs and will be
--   available to logging plugins.
--   Example:
--   return { w3c = "0af7651916cd43dd8448eb211c80319c" }
function _INJECTOR:get_formatted_trace_id(trace_id)
  return nil, "trace_id() not implemented in base class"
end


return _INJECTOR
