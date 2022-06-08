local constants     = require "kong.constants"
local meta          = require "kong.meta"
local http          = require "resty.http"
local kong_meta     = require "kong.meta"


local kong          = kong
local fmt           = string.format
local var           = ngx.var
local pairs         = pairs
local server_header = meta._SERVER_TOKENS
local conf_cache    = setmetatable({}, { __mode = "k" })


local function send(status, content, headers)
  if kong.configuration.enabled_headers[constants.HEADERS.VIA] then
    headers = kong.table.merge(headers) -- create a copy of headers
    headers[constants.HEADERS.VIA] = server_header
  end

  return kong.response.exit(status, content, headers)
end


local azure = {
  PRIORITY = 749,
  VERSION = kong_meta.version,
}


function azure:access(config)
  -- prepare and store updated config in cache
  local conf = conf_cache[config]
  if not conf then
    conf = {}
    for k,v in pairs(config) do
      conf[k] = v
    end
    conf.host = config.appname .. "." .. config.hostdomain
    conf.port = config.https and 443 or 80
    local f = (config.functionname or ""):match("^/*(.-)/*$")  -- drop pre/postfix slashes
    local p = (config.routeprefix or ""):match("^/*(.-)/*$")  -- drop pre/postfix slashes
    if p ~= "" then
      p = "/" .. p
    end
    conf.path = p .. "/" .. f

    conf_cache[config] = conf
  end
  config = conf

  local request_method = kong.request.get_method()
  local request_body = kong.request.get_raw_body()
  local request_headers = kong.request.get_headers()
  local request_args = kong.request.get_query()

  local upstream_uri = var.upstream_uri
  local path = conf.path
  local end1 = path:sub(-1, -1)
  local start2 = upstream_uri:sub(1, 1)
  if end1 == "/" then
    if start2 == "/" then
      path = path .. upstream_uri:sub(2,-1)
    else
      path = path .. upstream_uri
    end
  else
    if start2 == "/" then
      path = path .. upstream_uri
    else
      if upstream_uri ~= "" then
        path = path .. "/" .. upstream_uri
      end
    end
  end

  request_headers["host"] = nil  -- NOTE: OR return lowercase!
  request_headers["x-functions-key"] = config.apikey
  request_headers["x-functions-clientid"] = config.clientid


  local scheme = config.https and "https" or "http"
  local uri = conf.port and fmt("%s://%s:%d", scheme, conf.host, conf.port)
                         or fmt("%s://%s", scheme, conf.host)

  local client = http.new()
  client:set_timeout(config.timeout)
  local res, err = client:request_uri(uri, {
    method = request_method,
    path = path,
    body = request_body,
    query = request_args,
    headers = request_headers,
    ssl_verify = config.https_verify,
    keepalive_timeout = conf.keepalive,
  })

  if not res then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local response_headers = res.headers
  local response_status = res.status
  local response_content = res.body

  if var.http2 then
    response_headers["Connection"] = nil
    response_headers["Keep-Alive"] = nil
    response_headers["Proxy-Connection"] = nil
    response_headers["Upgrade"] = nil
    response_headers["Transfer-Encoding"] = nil
  end

  return send(response_status, response_content, response_headers)
end


return azure
