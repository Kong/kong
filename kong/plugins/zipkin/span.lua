--[[
The internal data structure is modeled off the ZipKin Span JSON Structure
This makes it cheaper to convert to JSON for submission to the ZipKin HTTP api;
which Jaegar also implements.
You can find it documented in this OpenAPI spec:
https://github.com/openzipkin/zipkin-api/blob/7e33e977/zipkin2-api.yaml#L280
]]

local span_methods = {}
local span_mt = {
  __index = span_methods,
}

local ngx_now = ngx.now

local function is(object)
  return getmetatable(object) == span_mt
end

local function new(tracer, context, name, start_timestamp)
  assert(tracer, "missing tracer")
  assert(context, "missing context")
  assert(type(name) == "string", "name should be a string")
  assert(type(start_timestamp) == "number", "invalid starting timestamp")
  return setmetatable({
    tracer_ = tracer,
    context_ = context,
    name = name,
    timestamp = start_timestamp,
    duration = nil,
    -- Avoid allocations until needed
    baggage = nil,
    tags = nil,
    logs = nil,
    n_logs = 0,
  }, span_mt)
end

function span_methods:context()
  return self.context_
end

function span_methods:tracer()
  return self.tracer_
end

function span_methods:set_operation_name(name)
  assert(type(name) == "string", "name should be a string")
  self.name = name
end

function span_methods:start_child_span(name, start_timestamp)
  return self.tracer_:start_span(name, {
    start_timestamp = start_timestamp,
    child_of = self,
  })
end

function span_methods:finish(finish_timestamp)
  assert(self.duration == nil, "span already finished")
  if finish_timestamp == nil then
    self.duration = ngx_now() - self.timestamp
  else
    assert(type(finish_timestamp) == "number")
    local duration = finish_timestamp - self.timestamp
    assert(duration >= 0, "invalid finish timestamp")
    self.duration = duration
  end
  if self.context_.should_sample then
    self.tracer_:report(self)
  end
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

function span_methods:get_tag(key)
  assert(type(key) == "string", "invalid tag key")
  local tags = self.tags
  if tags then
    return tags[key]
  else
    return nil
  end
end

function span_methods:each_tag()
  local tags = self.tags
  if tags == nil then return function() end end
  return next, tags
end

function span_methods:log(key, value, timestamp)
  assert(type(key) == "string", "invalid log key")
  -- `value` is allowed to be anything.
  if timestamp == nil then
    timestamp = ngx_now()
  else
    assert(type(timestamp) == "number", "invalid timestamp for log")
  end

  local log = {
    key = key,
    value = value,
    timestamp = timestamp,
  }

  local logs = self.logs
  if logs then
    local i = self.n_logs + 1
    logs[i] = log
    self.n_logs = i
  else
    logs = { log }
    self.logs = logs
    self.n_logs = 1
  end
  return true
end

function span_methods:log_kv(key_values, timestamp)
  if timestamp == nil then
    timestamp = self.tracer_:time()
  else
    assert(type(timestamp) == "number", "invalid timestamp for log")
  end

  local logs = self.logs
  local n_logs
  if logs then
    n_logs = 0
  else
    n_logs = self.n_logs
    logs = { }
    self.logs = logs
  end

  for key, value in pairs(key_values) do
    n_logs = n_logs + 1
    logs[n_logs] = {
      key = key,
      value = value,
      timestamp = timestamp,
    }
  end

  self.n_logs = n_logs
  return true
end

function span_methods:each_log()
  local i = 0
  return function(logs)
    if i >= self.n_logs then
      return
    end
    i = i + 1
    local log = logs[i]
    return log.key, log.value, log.timestamp
  end, self.logs
end

function span_methods:set_baggage_item(key, value)
  -- Create new context so that baggage is immutably passed around
  local newcontext = self.context_:clone_with_baggage_item(key, value)
  self.context_ = newcontext
  return true
end

function span_methods:get_baggage_item(key)
  return self.context_:get_baggage_item(key)
end

function span_methods:each_baggage_item()
  return self.context_:each_baggage_item()
end

return {
  new = new,
  is = is,
}
