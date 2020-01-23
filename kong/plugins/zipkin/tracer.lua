local ngx_now = ngx.now

local zipkin_span = require "kong.plugins.zipkin.span"
local zipkin_span_context = require "kong.plugins.zipkin.span_context"

local tracer_methods = {}
local tracer_mt = {
  __index = tracer_methods,
}

local function is(object)
  return getmetatable(object) == tracer_mt
end

local no_op_reporter = {
  report = function() end,
}
local no_op_sampler = {
  sample = function() return false end,
}

-- Make injectors and extractors weakly keyed so that unreferenced formats get dropped
local injectors_metatable = {
  __mode = "k",
}
local extractors_metatable = {
  __mode = "k",
}

local function new(reporter, sampler)
  if reporter == nil then
    reporter = no_op_reporter
  end
  if sampler == nil then
    sampler = no_op_sampler
  end
  return setmetatable({
    injectors = setmetatable({}, injectors_metatable),
    extractors = setmetatable({}, extractors_metatable),
    reporter = reporter,
    sampler = sampler,
  }, tracer_mt)
end

function tracer_methods:start_span(name, options)
  local context, child_of, references, tags, extra_tags, start_timestamp
  if options ~= nil then
    child_of = options.child_of
    references = options.references
    if child_of ~= nil then
      assert(references == nil, "cannot specify both references and child_of")
      if zipkin_span.is(child_of) then
        child_of = child_of:context()
      else
        assert(zipkin_span_context.is(child_of), "child_of should be a span or span context")
      end
    end
    if references ~= nil then
      assert(type(references) == "table", "references should be a table")
      error("references NYI")
    end
    tags = options.tags
    if tags ~= nil then
      assert(type(tags) == "table", "tags should be a table")
    end
    start_timestamp = options.start_timestamp
    -- Allow zipkin_span.new to validate
  end
  if start_timestamp == nil then
    start_timestamp = ngx_now()
  end
  if child_of then
    context = child_of:child()
  else
    local should_sample
    should_sample, extra_tags = self.sampler:sample(name)
    context = zipkin_span_context.new(nil, nil, nil, should_sample)
  end
  local span = zipkin_span.new(self, context, name, start_timestamp)
  if extra_tags then
    for k, v in pairs(extra_tags) do
      span:set_tag(k, v)
    end
  end
  if tags then
    for k, v in pairs(tags) do
      span:set_tag(k, v)
    end
  end
  return span
end

function tracer_methods:report(span)
  return self.reporter:report(span)
end

function tracer_methods:register_injector(format, injector)
  assert(format, "invalid format")
  assert(injector, "invalid injector")
  self.injectors[format] = injector
  return true
end

function tracer_methods:register_extractor(format, extractor)
  assert(format, "invalid format")
  assert(extractor, "invalid extractor")
  self.extractors[format] = extractor
  return true
end

function tracer_methods:inject(context, format, carrier)
  if zipkin_span.is(context) then
    context = context:context()
  else
    assert(zipkin_span_context.is(context), "context should be a span or span context")
  end
  local injector = self.injectors[format]
  if injector == nil then
    error("Unknown format: " .. format)
  end
  return injector(context, carrier)
end

function tracer_methods:extract(format, carrier)
  local extractor = self.extractors[format]
  if extractor == nil then
    error("Unknown format: " .. format)
  end
  return extractor(carrier)
end

return {
  new = new,
  is = is,
}
