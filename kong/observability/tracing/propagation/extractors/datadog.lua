local _EXTRACTOR        = require "kong.observability.tracing.propagation.extractors._base"
local bn                = require "resty.openssl.bn"

local from_dec          = bn.from_dec

local DATADOG_EXTRACTOR = _EXTRACTOR:new({
  headers_validate = {
    any = {
      "x-datadog-trace-id",
      "x-datadog-parent-id",
      "x-datadog-sampling-priority",
    }
  }
})


function DATADOG_EXTRACTOR:get_context(headers)
  local should_sample = headers["x-datadog-sampling-priority"]
  if should_sample == "1" or should_sample == "2" then
    should_sample = true
  elseif should_sample == "0" or should_sample == "-1" then
    should_sample = false
  elseif should_sample ~= nil then
    kong.log.warn("x-datadog-sampling-priority header invalid; ignoring.")
    return
  end

  local trace_id = headers["x-datadog-trace-id"]
  if trace_id then
    trace_id = trace_id:match("^%s*(%d+)%s*$")
    if not trace_id then
      kong.log.warn("x-datadog-trace-id header invalid; ignoring.")
    end
  end

  local parent_id = headers["x-datadog-parent-id"]
  if parent_id then
    parent_id = parent_id:match("^%s*(%d+)%s*$")
    if not parent_id then
      kong.log.warn("x-datadog-parent-id header invalid; ignoring.")
    end
  end

  if not trace_id then
    parent_id = nil
  end

  trace_id  = trace_id and from_dec(trace_id):to_binary() or nil
  parent_id = parent_id and from_dec(parent_id):to_binary() or nil

  return {
    trace_id      = trace_id,
    -- in datadog "parent" is the parent span of the receiver
    -- Internally we call that "span_id"
    span_id       = parent_id,
    parent_id     = nil,
    should_sample = should_sample,
  }
end

return DATADOG_EXTRACTOR
