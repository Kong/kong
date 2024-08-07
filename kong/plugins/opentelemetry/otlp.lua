require "kong.plugins.opentelemetry.proto"
local pb = require "pb"
local new_tab = require "table.new"
local nkeys = require "table.nkeys"
local tablepool = require "tablepool"
local deep_copy = require("kong.tools.table").deep_copy

local kong = kong
local insert = table.insert
local tablepool_fetch = tablepool.fetch
local tablepool_release = tablepool.release
local table_merge = require("kong.tools.table").table_merge
local setmetatable = setmetatable

local TRACE_ID_LEN = 16
local SPAN_ID_LEN  = 8
local NULL = "\0"
local POOL_OTLP = "KONG_OTLP"
local EMPTY_TAB = {}

local PB_STATUS = {}
for i = 0, 2 do
  PB_STATUS[i] = { code = i }
end

local KEY_TO_ATTRIBUTE_TYPES = {
  ["http.status_code"] = "int_value",
}

local TYPE_TO_ATTRIBUTE_TYPES = {
  string = "string_value",
  number = "double_value",
  boolean = "bool_value",
}

local function transform_attributes(attr)
  if type(attr) ~= "table" then
    error("invalid attributes", 2)
  end

  local pb_attributes = new_tab(nkeys(attr), 0)
  for k, v in pairs(attr) do

    local attribute_type = KEY_TO_ATTRIBUTE_TYPES[k] or TYPE_TO_ATTRIBUTE_TYPES[type(v)]

    insert(pb_attributes, {
      key = k,
      value = attribute_type and { [attribute_type] = v } or EMPTY_TAB
    })
  end

  return pb_attributes
end

local function transform_events(events)
  if type(events) ~= "table" then
    return nil
  end

  local pb_events = new_tab(#events, 0)
  for _, evt in ipairs(events) do
    local pb_evt = {
      name = evt.name,
      time_unix_nano = evt.time_ns,
      -- dropped_attributes_count = 0,
    }

    if evt.attributes then
      pb_evt.attributes = transform_attributes(evt.attributes)
    end

    insert(pb_events, pb_evt)
  end

  return pb_events
end

local function id_formatter(length)
  return function(id)
    local len = #id
    if len > length then
      return id:sub(-length)

    elseif len < length then
      return NULL:rep(length - len) .. id
    end

    return id
  end
end

local to_ot_trace_id, to_ot_span_id
do
  -- translate the trace_id and span_id to otlp format
  to_ot_trace_id = id_formatter(TRACE_ID_LEN)
  to_ot_span_id  = id_formatter(SPAN_ID_LEN)
end

-- this function is to prepare span to be encoded and sent via grpc
-- TODO: renaming this to encode_span
local function transform_span(span)
  assert(type(span) == "table")

  local pb_span = {
    trace_id = to_ot_trace_id(span.trace_id),
    span_id = span.span_id,
    -- trace_state = "",
    parent_span_id = span.parent_id and
                     to_ot_span_id(span.parent_id) or "",
    name = span.name,
    kind = span.kind or 0,
    start_time_unix_nano = span.start_time_ns,
    end_time_unix_nano = span.end_time_ns,
    attributes = span.attributes and transform_attributes(span.attributes),
    -- dropped_attributes_count = 0,
    events = span.events and transform_events(span.events),
    -- dropped_events_count = 0,
    -- links = EMPTY_TAB,
    -- dropped_links_count = 0,
    status = span.status and PB_STATUS[span.status],
  }

  return pb_span
end

local encode_traces, encode_logs, prepare_logs
do
  local attributes_cache = setmetatable({}, { __mode = "k" })
  local function default_resource_attributes()
    return {
      ["service.name"] = "kong",
      ["service.instance.id"] = kong and kong.node.get_id(),
      ["service.version"] = kong and kong.version,
    }
  end

  local function render_resource_attributes(attributes)
    attributes = attributes or EMPTY_TAB

    local resource_attributes = attributes_cache[attributes]
    if resource_attributes then
      return resource_attributes
    end

    local default_attributes = default_resource_attributes()
    resource_attributes = table_merge(default_attributes, attributes)

    resource_attributes = transform_attributes(resource_attributes)
    attributes_cache[attributes] = resource_attributes

    return resource_attributes
  end

  local pb_memo_trace = {
    resource_spans = {
      { resource = {
          attributes = {}
        },
        scope_spans = {
          { scope = {
              name = "kong-internal",
              version = "0.1.0",
            },
            spans = {}, },
        }, },
    },
  }

  encode_traces = function(spans, resource_attributes)
    local tab = tablepool_fetch(POOL_OTLP, 0, 2)
    if not tab.resource_spans then
      tab.resource_spans = deep_copy(pb_memo_trace.resource_spans)
    end

    local resource = tab.resource_spans[1].resource
    resource.attributes = render_resource_attributes(resource_attributes)

    local scoped = tab.resource_spans[1].scope_spans[1]
    scoped.spans = spans
    local pb_data = pb.encode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", tab)

    -- remove reference
    scoped.spans = nil
    tablepool_release(POOL_OTLP, tab, true) -- no clear

    return pb_data
  end

  local pb_memo_log = {
    resource_logs = {
      { resource = {
          attributes = {}
        },
        scope_logs = {
          { scope = {
              name = "kong-internal",
              version = "0.1.0",
            },
            log_records = {}, },
        }, },
    },
  }

  encode_logs = function(log_batch, resource_attributes)
    local tab = tablepool_fetch(POOL_OTLP, 0, 3)
    if not tab.resource_logs then
      tab.resource_logs = deep_copy(pb_memo_log.resource_logs)
    end

    local resource = tab.resource_logs[1].resource
    resource.attributes = render_resource_attributes(resource_attributes)

    local scoped = tab.resource_logs[1].scope_logs[1]

    scoped.log_records = log_batch

    local pb_data = pb.encode("opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest", tab)

    -- remove reference
    scoped.logs = nil
    tablepool_release(POOL_OTLP, tab, true) -- no clear

    return pb_data
  end

  -- see: kong/include/opentelemetry/proto/logs/v1/logs.proto
  local map_severity = {
    [ngx.DEBUG]  = {  5, "DEBUG" },
    [ngx.INFO]   = {  9, "INFO" },
    [ngx.NOTICE] = { 11, "NOTICE" },
    [ngx.WARN]   = { 13, "WARN" },
    [ngx.ERR]    = { 17, "ERR" },
    [ngx.CRIT]   = { 19, "CRIT" },
    [ngx.ALERT]  = { 21, "ALERT" },
    [ngx.EMERG]  = { 23, "EMERG" },
  }

  prepare_logs = function(logs, trace_id, flags)
    for _, log in ipairs(logs) do
      local severity = map_severity[log.log_level]
      log.severity_number = severity and severity[1]
      log.severity_text = severity and severity[2]
      log.log_level = nil
      log.trace_id = trace_id
      log.flags = flags
      log.attributes = transform_attributes(log.attributes)
      log.body = { string_value = log.body }
    end

    return logs
  end
end

return {
  to_ot_trace_id = to_ot_trace_id,
  transform_span = transform_span,
  encode_traces = encode_traces,
  encode_logs = encode_logs,
  prepare_logs = prepare_logs,
}
