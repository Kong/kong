local constants     = require "kong.constants"
local http          = require "resty.http"
local kong_meta     = require "kong.meta"


local kong          = kong
local fmt           = string.format
local byte          = string.byte
local match         = string.match
local var           = ngx.var

local server_tokens = kong_meta._SERVER_TOKENS
local VIA_HEADER    = constants.HEADERS.VIA


local SLASH = byte("/")
local STRIP_SLASHES_PATTERN = "^/*(.-)/*$"


local azure = {
  PRIORITY = 749,
  VERSION = kong_meta.version,
}


function azure:access(conf)
  local path do

    -- strip pre-/postfix slashes
    path = match(conf.routeprefix or "", STRIP_SLASHES_PATTERN)
    local func = match(conf.functionname or "", STRIP_SLASHES_PATTERN)

    if path ~= "" then
      path = "/" .. path
    end

    local functionname_first_byte = byte(func, 1)
    if functionname_first_byte == SLASH then
      path = path .. func
    else
      path = path .. "/" .. func
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

  if kong.configuration.enabled_headers[VIA_HEADER] then
    local outbound_via = (var.http2 and "2 " or "1.1 ") .. server_tokens
    response_headers[VIA_HEADER] = response_headers[VIA_HEADER] and response_headers[VIA_HEADER] .. ", " .. outbound_via
                                   or outbound_via
 end

  return kong.response.exit(res.status, res.body, response_headers)
end


return azure
