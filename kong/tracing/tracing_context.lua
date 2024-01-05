local table_new = require "table.new"

local ngx = ngx


local function init_tracing_context(ctx)
  ctx.TRACING_CONTEXT = {
    -- trace ID information which includes its raw value (binary) and all the
    -- available formats set during headers propagation
    trace_id = {
      raw = nil,
      formatted = table_new(0, 6),
    },
    -- Unlinked spans are spans that were created (to generate their ID)
    -- but not added to `KONG_SPANS` (because their execution details were not
    -- yet available).
    unlinked_spans = table_new(0, 1)
  }

  return ctx.TRACING_CONTEXT
end


local function get_tracing_context(ctx)
  ctx = ctx or ngx.ctx

  if not ctx.TRACING_CONTEXT then
    return init_tracing_context(ctx)
  end

  return ctx.TRACING_CONTEXT
end


-- Performs a table merge to add trace ID formats to the current request's
-- trace ID and returns a table containing all the formats.
--
-- Plugins can handle different formats of trace ids depending on their headers
-- configuration, multiple plugins executions may result in additional formats
-- of the current request's trace id.
--
-- Each item in the resulting table represents a format associated with the
-- trace ID for the current request.
--
-- @param trace_id_new_fmt table containing the trace ID formats to be added
-- @param ctx table the current ctx, if available
-- @returns propagation_trace_id_all_fmt table contains all the formats for
-- the current request
--
-- @example
--
--    propagation_trace_id_all_fmt = { datadog = "1234",
--                                     w3c     = "abcd" }
--
--    trace_id_new_fmt             = { ot = "abcd",
--                                     w3c = "abcd" }
--
--    propagation_trace_id_all_fmt = { datadog = "1234",
--                                     ot = "abcd",
--                                     w3c = "abcd" }
--
local function add_trace_id_formats(trace_id_new_fmt, ctx)
  local tracing_context = get_tracing_context(ctx)
  local trace_id_all_fmt = tracing_context.trace_id.formatted

  if next(trace_id_all_fmt) == nil then
    tracing_context.trace_id.formatted = trace_id_new_fmt
    return trace_id_new_fmt
  end

  -- add new formats to existing trace ID formats table
  for format, value in pairs(trace_id_new_fmt) do
    trace_id_all_fmt[format] = value
  end

  return trace_id_all_fmt
end


local function get_raw_trace_id(ctx)
  local tracing_context = get_tracing_context(ctx)
  return tracing_context.trace_id.raw
end


local function set_raw_trace_id(trace_id, ctx)
  local tracing_context = get_tracing_context(ctx)
  tracing_context.trace_id.raw = trace_id
end


local function get_unlinked_span(name, ctx)
  local tracing_context = get_tracing_context(ctx)
  return tracing_context.unlinked_spans[name]
end


local function set_unlinked_span(name, span, ctx)
  local tracing_context = get_tracing_context(ctx)
  tracing_context.unlinked_spans[name] = span
end



return {
  add_trace_id_formats = add_trace_id_formats,
  get_raw_trace_id = get_raw_trace_id,
  set_raw_trace_id = set_raw_trace_id,
  get_unlinked_span = get_unlinked_span,
  set_unlinked_span = set_unlinked_span,
}
