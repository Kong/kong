--[[
The internal data structure is modeled off the ZipKin Span JSON Structure
This makes it cheaper to convert to JSON for submission to the ZipKin HTTP api;
which Jaegar also implements.
You can find it documented in this OpenAPI spec:
https://github.com/openzipkin/zipkin-api/blob/7e33e977/zipkin2-api.yaml#L280
]]

local rand_bytes = require("kong.tools.rand").get_rand_bytes

local floor = math.floor

local span_methods = {}
local span_mt = {
  __index = span_methods,
}


local baggage_mt = {
  __newindex = function()
    error("attempt to set immutable baggage")
  end,
}


local function generate_span_id()
  return rand_bytes(8)
end


local function new(kind, name, start_timestamp_mu,
                   should_sample, trace_id,
                   span_id, parent_id, baggage)
  assert(kind == "SERVER" or kind == "CLIENT", "invalid span kind")
  assert(type(name) == "string" and name ~= "", "invalid span name")
  assert(type(start_timestamp_mu) == "number" and start_timestamp_mu >= 0,
         "invalid span start_timestamp")
  assert(type(trace_id) == "string", "invalid trace id")

  if span_id == nil then
    span_id = generate_span_id()
  else
    assert(type(span_id) == "string", "invalid span id")
  end

  if parent_id ~= nil then
    assert(type(parent_id) == "string", "invalid parent id")
  end

  if baggage then
    setmetatable(baggage, baggage_mt)
  end

  return setmetatable({
    kind = kind,
    trace_id = trace_id,
    span_id = span_id,
    parent_id = parent_id,
    name = name,
    timestamp = floor(start_timestamp_mu),
    should_sample = should_sample,
    baggage = baggage,
    n_logs = 0,
  }, span_mt)
end


function span_methods:new_child(kind, name, start_timestamp_mu)
  return new(
    kind,
    name,
    start_timestamp_mu,
    self.should_sample,
    self.trace_id,
    generate_span_id(),
    self.span_id,
    self.baggage
  )
end


function span_methods:finish(finish_timestamp_mu)
  assert(self.duration == nil, "span already finished")
  assert(type(finish_timestamp_mu) == "number" and finish_timestamp_mu >= 0,
         "invalid span finish timestamp")
  local duration = finish_timestamp_mu - self.timestamp
  assert(duration >= 0, "invalid span duration")
  self.duration = floor(duration)
  return true
end


function span_methods:set_tag(key, value)
  assert(type(key) == "string", "invalid tag key")
  if value ~= nil then -- Validate value
    local vt = type(value)
    assert(vt == "string" or vt == "number" or vt == "boolean",
      "invalid tag value (expected string, number, boolean or nil)")
  end
  local tags = self.tags
  if tags then
    tags[key] = value
  elseif value ~= nil then
    tags = {
      [key] = value
    }
    self.tags = tags
  end
  return true
end


function span_methods:each_tag()
  local tags = self.tags
  if tags == nil then return function() end end
  return next, tags
end


function span_methods:annotate(value, timestamp_mu)
  assert(type(value) == "string", "invalid annotation value")
  assert(type(timestamp_mu) == "number" and timestamp_mu >= 0, "invalid annotation timestamp")

  local annotation = {
    value = value,
    timestamp = floor(timestamp_mu),
  }

  local annotations = self.annotations
  if annotations then
    annotations[#annotations + 1] = annotation
  else
    self.annotations = { annotation }
  end
  return true
end


function span_methods:each_baggage_item()
  local baggage = self.baggage
  if baggage == nil then return function() end end
  return next, baggage
end


return {
  new = new,
}
