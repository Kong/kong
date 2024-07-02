local _EXTRACTOR        = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils = require "kong.observability.tracing.propagation.utils"

local split = require "kong.tools.string".split
local strip = require "kong.tools.string".strip

local from_hex = propagation_utils.from_hex
local match    = string.match
local ipairs = ipairs
local type = type

local AWS_KV_PAIR_DELIM = ";"
local AWS_KV_DELIM = "="
local AWS_TRACE_ID_KEY = "Root"
local AWS_TRACE_ID_LEN = 35
local AWS_TRACE_ID_PATTERN = "^(%x+)%-(%x+)%-(%x+)$"
local AWS_TRACE_ID_VERSION = "1"
local AWS_TRACE_ID_TIMESTAMP_LEN = 8
local AWS_TRACE_ID_UNIQUE_ID_LEN = 24
local AWS_PARENT_ID_KEY = "Parent"
local AWS_PARENT_ID_LEN = 16
local AWS_SAMPLED_FLAG_KEY = "Sampled"

local AWS_EXTRACTOR = _EXTRACTOR:new({
  headers_validate = {
    any = { "x-amzn-trace-id" }
  }
})


function AWS_EXTRACTOR:get_context(headers)
  local aws_header = headers["x-amzn-trace-id"]

  if type(aws_header) ~= "string" then
    return
  end

  local trace_id, parent_id, should_sample

  -- The AWS trace header consists of multiple `key=value` separated by a delimiter `;`
  -- We can retrieve the trace id with the `Root` key, the span id with the `Parent`
  -- key and the sampling parameter with the `Sampled` flag. Extra information should be ignored.
  --
  -- The trace id has a custom format: `version-timestamp-uniqueid` and an opentelemetry compatible
  -- id can be deduced by concatenating the timestamp and uniqueid.
  --
  -- https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html#xray-concepts-tracingheader
  for _, key_pair in ipairs(split(aws_header, AWS_KV_PAIR_DELIM)) do
    local key_pair_list = split(key_pair, AWS_KV_DELIM)
    local key = strip(key_pair_list[1])
    local value = strip(key_pair_list[2])

    if key == AWS_TRACE_ID_KEY then
      local version, timestamp_subset, unique_id_subset = match(value, AWS_TRACE_ID_PATTERN)

      if #value ~= AWS_TRACE_ID_LEN or version ~= AWS_TRACE_ID_VERSION
      or #timestamp_subset ~= AWS_TRACE_ID_TIMESTAMP_LEN
      or #unique_id_subset ~= AWS_TRACE_ID_UNIQUE_ID_LEN then
        kong.log.warn("invalid aws header trace id; ignoring.")
        return
      end

      trace_id = from_hex(timestamp_subset .. unique_id_subset)

    elseif key == AWS_PARENT_ID_KEY then
      if #value ~= AWS_PARENT_ID_LEN then
        kong.log.warn("invalid aws header parent id; ignoring.")
        return
      end
      parent_id = from_hex(value)

    elseif key == AWS_SAMPLED_FLAG_KEY then
      if value ~= "0" and value ~= "1" then
        kong.log.warn("invalid aws header sampled flag; ignoring.")
        return
      end

      should_sample = value == "1"
    end
  end

  return {
    trace_id      = trace_id,
    -- in aws "parent" is the parent span of the receiver
    -- Internally we call that "span_id"
    span_id       = parent_id,
    parent_id     = nil,
    should_sample = should_sample,
  }
end

return AWS_EXTRACTOR
