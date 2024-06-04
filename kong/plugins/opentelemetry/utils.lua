-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http = require "resty.http"
local clone = require "table.clone"

local tostring = tostring
local null = ngx.null


local CONTENT_TYPE_HEADER_NAME = "Content-Type"
local DEFAULT_CONTENT_TYPE_HEADER = "application/x-protobuf"
local DEFAULT_HEADERS = {
  [CONTENT_TYPE_HEADER_NAME] = DEFAULT_CONTENT_TYPE_HEADER
}

local _log_prefix = "[otel] "

local function http_export_request(conf, pb_data, headers)
  local httpc = http.new()
  httpc:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)
  local res, err = httpc:request_uri(conf.endpoint, {
    method = "POST",
    body = pb_data,
    headers = headers,
  })

  if not res then
    return false, "failed to send request: " .. err

  elseif res and res.status ~= 200 then
    return false, "response error: " .. tostring(res.status) .. ", body: " .. tostring(res.body)
  end

  return true
end


local function get_headers(conf_headers)
  if not conf_headers or conf_headers == null then
    return DEFAULT_HEADERS
  end

  if conf_headers[CONTENT_TYPE_HEADER_NAME] then
    return conf_headers
  end

  local headers = clone(conf_headers)
  headers[CONTENT_TYPE_HEADER_NAME] = DEFAULT_CONTENT_TYPE_HEADER
  return headers
end


return {
  http_export_request = http_export_request,
  get_headers = get_headers,
  _log_prefix = _log_prefix,
}
