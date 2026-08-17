local _EXTRACTOR        = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils = require "kong.observability.tracing.propagation.utils"
local bn                = require "resty.openssl.bn"

local type = type
local ngx_re_match = ngx.re.match

local from_hex          = propagation_utils.from_hex
local from_dec          = bn.from_dec

local GCP_TRACECONTEXT_REGEX = "^(?<trace_id>[0-9a-f]{32})/(?<span_id>[0-9]{1,20})(;o=(?<trace_flags>[0-9]))?$"

local GCP_EXTRACTOR = _EXTRACTOR:new({
  headers_validate = {
    any = { "x-cloud-trace-context" }
  }
})


function GCP_EXTRACTOR:get_context(headers)
  local gcp_header = headers["x-cloud-trace-context"]

  if type(gcp_header) ~= "string" then
    return
  end

  local match, err = ngx_re_match(gcp_header, GCP_TRACECONTEXT_REGEX, 'jo')
  if not match then
    local warning = "invalid GCP header"
    if err then
      warning = warning .. ": " .. err
    end

    kong.log.warn(warning .. "; ignoring.")
    return
  end

  return {
    trace_id      = from_hex(match["trace_id"]),
    span_id       = from_dec(match["span_id"]):to_binary(),
    parent_id     = nil,
    should_sample = match["trace_flags"] == "1",
  }
end

return GCP_EXTRACTOR
