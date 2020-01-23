--[[
Span contexts should be immutable
]]

local rand_bytes = require "openssl.rand".bytes

-- For zipkin compat, use 128 bit trace ids
local function generate_trace_id()
  return rand_bytes(16)
end

-- For zipkin compat, use 64 bit span ids
local function generate_span_id()
  return rand_bytes(8)
end

local span_context_methods = {}
local span_context_mt = {
  __index = span_context_methods,
}

local function is(object)
  return getmetatable(object) == span_context_mt
end

local baggage_mt = {
  __newindex = function()
    error("attempt to set immutable baggage")
  end,
}

-- Public constructor
local function new(trace_id, span_id, parent_id, should_sample, baggage)
  if trace_id == nil then
    trace_id = generate_trace_id()
  else
    assert(type(trace_id) == "string", "invalid trace id")
  end
  if span_id == nil then
    span_id = generate_span_id()
  else
    assert(type(span_id) == "string", "invalid span id")
  end
  if parent_id ~= nil then
    assert(type(parent_id) == "string", "invalid parent id")
  end
  if baggage then
    local new_baggage = {}
    for key, value in pairs(baggage) do
      assert(type(key) == "string", "invalid baggage key")
      assert(type(value) == "string", "invalid baggage value")
      new_baggage[key] = value
    end
    baggage = setmetatable(new_baggage, baggage_mt)
  end
  return setmetatable({
    trace_id = trace_id,
    span_id = span_id,
    parent_id = parent_id,
    should_sample = should_sample,
    baggage = baggage,
  }, span_context_mt)
end

function span_context_methods:child()
  return setmetatable({
    trace_id = self.trace_id,
    span_id = generate_span_id(),
    parent_id = self.span_id,
    -- If parent was sampled, sample the child
    should_sample = self.should_sample,
    baggage = self.baggage,
  }, span_context_mt)
end

-- New from existing but with an extra baggage item
function span_context_methods:clone_with_baggage_item(key, value)
  assert(type(key) == "string", "invalid baggage key")
  assert(type(value) == "string", "invalid baggage value")
  local new_baggage = {}
  if self.baggage then
    for k, v in pairs(self.baggage) do
      new_baggage[k] = v
    end
  end
  new_baggage[key] = value
  return setmetatable({
    trace_id = self.trace_id,
    span_id = self.span_id,
    parent_id = self.parent_id,
    should_sample = self.should_sample,
    baggage = setmetatable(new_baggage, baggage_mt),
  }, span_context_mt)
end

function span_context_methods:get_baggage_item(key)
  assert(type(key) == "string", "invalid baggage key")
  local baggage = self.baggage
  if baggage == nil then
    return nil
  else
    return baggage[key]
  end
end

function span_context_methods:each_baggage_item()
  local baggage = self.baggage
  if baggage == nil then return function() end end
  return next, baggage
end

return {
  new = new,
  is = is,
}
