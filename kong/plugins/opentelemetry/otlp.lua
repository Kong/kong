require "kong.plugins.opentelemetry.proto"
local pb = require "pb"
local new_tab = require "table.new"
local nkeys = require "table.nkeys"
local tablepool = require "tablepool"
local utils = require "kong.tools.utils"

local kong = kong
local insert = table.insert
local tablepool_fetch = tablepool.fetch
local tablepool_release = tablepool.release
local deep_copy = utils.deep_copy
local table_merge = utils.table_merge

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

local function transform_span(span)
  assert(type(span) == "table")

  local pb_span = {
    trace_id = span.trace_id,
    span_id = span.span_id,
    -- trace_state = "",
    parent_span_id = span.parent_id or "",
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

local encode_traces
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

  local pb_memo = {
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
      tab.resource_spans = deep_copy(pb_memo.resource_spans)
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
end

return {
  transform_span = transform_span,
  encode_traces = encode_traces,
}
