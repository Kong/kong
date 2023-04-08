-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants     = require "kong.constants"
local meta          = require "kong.meta"
local http          = require "resty.http"
local kong_meta     = require "kong.meta"


local kong          = kong
local fmt           = string.format
local sub           = string.sub
local find          = string.find
local byte          = string.byte
local match         = string.match
local var           = ngx.var
local server_header = meta._SERVER_TOKENS


local SLASH = byte("/")
local STRIP_SLASHES_PATTERN = "^/*(.-)/*$"


local azure = {
  PRIORITY = 749,
  VERSION = kong_meta.core_version,
}


function azure:access(conf)
  local path do
    -- strip any query args
    local upstream_uri = var.upstream_uri or var.request_uri
    local s = find(upstream_uri, "?", 1, true)
    upstream_uri = s and sub(upstream_uri, 1, s - 1) or upstream_uri

    -- strip pre-/postfix slashes
    path = match(conf.routeprefix or "", STRIP_SLASHES_PATTERN)
    local func = match(conf.functionname or "", STRIP_SLASHES_PATTERN)

    if path ~= "" then
      path = "/" .. path
    end

    path = path .. "/" .. func

    -- concatenate path with upstream uri
    local upstream_uri_first_byte = byte(upstream_uri, 1)
    local path_last_byte = byte(path, -1)
    if path_last_byte == SLASH then
      if upstream_uri_first_byte == SLASH then
        path = path .. sub(upstream_uri, 2, -1)
      else
        path = path .. upstream_uri
      end

    else
      if upstream_uri_first_byte == SLASH then
        path = path .. upstream_uri
      elseif upstream_uri ~= "" then
        path = path .. "/" .. upstream_uri
      end
    end
  end

  local host = conf.appname .. "." .. conf.hostdomain
  local scheme = conf.https and "https" or "http"
  local port = conf.https and 443 or 80
  local uri = fmt("%s://%s:%d", scheme, host, port)

  local request_headers = kong.request.get_headers()
  request_headers["host"] = nil  -- NOTE: OR return lowercase!
  request_headers["x-functions-key"] = conf.apikey
  request_headers["x-functions-clientid"] = conf.clientid

  local client = http.new()
  client:set_timeout(conf.timeout)
  local res, err = client:request_uri(uri, {
    method = kong.request.get_method(),
    path = path,
    body = kong.request.get_raw_body(),
    query = kong.request.get_query(),
    headers = request_headers,
    ssl_verify = conf.https_verify,
    keepalive_timeout = conf.keepalive,
  })

  if not res then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local response_headers = res.headers
  if var.http2 then
    response_headers["Connection"] = nil
    response_headers["Keep-Alive"] = nil
    response_headers["Proxy-Connection"] = nil
    response_headers["Upgrade"] = nil
    response_headers["Transfer-Encoding"] = nil
  end

  if kong.configuration.enabled_headers[constants.HEADERS.VIA] then
    response_headers[constants.HEADERS.VIA] = server_header
  end

  return kong.response.exit(res.status, res.body, response_headers)
end


return azure
