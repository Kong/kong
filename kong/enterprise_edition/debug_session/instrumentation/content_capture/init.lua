-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cc_modes = require "kong.enterprise_edition.debug_session.common".CONTENT_CAPTURE_MODES
local credit_card = require "kong.enterprise_edition.debug_session.instrumentation.content_capture.sanitizers.credit_card"
local parse_mime_type = require "kong.tools.mime_type".parse_mime_type

local fmt = string.format

local MAX_BODY_SIZE = 128 * 1e3
local SUPPORTED_CONTENT_TYPES = {
  ["application/json"] = true,
  ["application/x-www-form-urlencoded"] = true,
  ["application/xml"] = true,
  ["application/xhtml+xml"] = true,
  ["text/xml"] = true,
  ["text/plain"] = true,
  ["text/css"] = true,
  ["text/csv"] = true,
  ["text/event-stream"] = true,
  ["text/html"] = true,
  ["text/javascript"] = true,
}
local SANITIZERS = {
  credit_card,
}


local function validate_content_type(content_type_header_v)
  local type, subtype = parse_mime_type(content_type_header_v)
  if not type or not subtype then
    return nil, fmt("unsupported content-type: %s", content_type_header_v)
  end

  local content_type = fmt("%s/%s", type, subtype):lower()
  if not SUPPORTED_CONTENT_TYPES[content_type] then
    return nil, fmt("unsupported content-type: %s", content_type)
  end

  return true
end


local function validate_body_content_type(body, err, content_type)
  if not body and not content_type then
    -- silently exit from req/resp with no body
    return
  end

  if not content_type then
    return nil, "missing content-type header"
  end

  if not body then
    -- if get_raw_body returns with no error it's ok to silently exit
    return nil, err and fmt("failed to get body: %s", err) or nil
  end

  if #body > MAX_BODY_SIZE then
    return nil, fmt("body size: %d exceeds limit: %d", #body, MAX_BODY_SIZE)
  end

  return validate_content_type(content_type)
end


-- executes all the configured sanitizers one by one
-- the output of one sanitizer is passed as input to the next one
-- therefore order of execution of sanitizers matter and this should
-- be taken into account when adding new sanitizers
local function sanitize(content)
  local err
  for _, sanitizer in ipairs(SANITIZERS) do
    content, err = sanitizer.sanitize(content)
    if err then
      return nil, err
    end
  end

  return content
end


local _M = {}


function _M.request_body()
  if not kong.debug_session:content_capture_enabled(cc_modes.BODY) then
    return
  end

  local body, err = kong.request.get_raw_body(MAX_BODY_SIZE)
  local content_type = kong.request.get_header("content-type")

  local ok, err = validate_body_content_type(body, err, content_type)
  if not ok then
    return nil, err and fmt("validation failed: %s", err)
  end

  body, err = sanitize(body)
  if not body then
    return nil, fmt("failed to sanitize request body: %s", err)
  end

  kong.debug_session:set_request_body(body)
  return true
end


function _M.response_body()
  if not kong.debug_session:content_capture_enabled(cc_modes.BODY) then
    return
  end

  local body, err = kong.response.get_raw_body()
  local content_type = kong.response.get_header("content-type")

  local ok, err = validate_body_content_type(body, err, content_type)
  if not ok then
    return nil, err and fmt("validation failed: %s", err)
  end

  body, err = sanitize(body)
  if not body then
    return nil, fmt("failed to sanitize response body: %s", err)
  end

  kong.debug_session:set_response_body(body)
  return true
end


function _M.request_headers()
  if not kong.debug_session:content_capture_enabled(cc_modes.HEADERS) then
    return
  end

  local headers = kong.request.get_headers()
  kong.debug_session:set_request_headers(headers)
end


function _M.response_headers()
  if not kong.debug_session:content_capture_enabled(cc_modes.HEADERS) then
    return
  end

  local headers = kong.response.get_headers()
  kong.debug_session:set_response_headers(headers)
end


return _M
