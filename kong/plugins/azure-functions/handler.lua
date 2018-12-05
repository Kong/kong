local BasePlugin    = require "kong.plugins.base_plugin"
local constants     = require "kong.constants"
local meta          = require "kong.meta"
local http          = require "resty.http"


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


local azure = BasePlugin:extend()

azure.PRIORITY = 749
azure.VERSION = "0.1.1"


function azure:new()
  azure.super.new(self, "azure-functions")
end


function azure:access(config)
  azure.super.access(self)

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

  local client = http.new()
  local request_method = kong.request.get_method()
  local request_body = kong.request.get_raw_body()
  local request_headers = kong.request.get_headers()
  local request_args = kong.request.get_query()

  client:set_timeout(config.timeout)

  local ok, err = client:connect(config.host, config.port)
  if not ok then
    kong.log.err("could not connect to Azure service: ", err)
    return kong.response.exit(500, { message = "An unexpected error ocurred" })
  end

  if config.https then
    local ok2, err2 = client:ssl_handshake(false, config.host, config.https_verify)
    if not ok2 then
      kong.log.err("could not perform SSL handshake : ", err2)
      return kong.response.exit(500, { message = "An unexpected error ocurred" })
    end
  end

  local upstream_uri = ngx.var.upstream_uri
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

  local res
  res, err = client:request {
    method  = request_method,
    path    = path,
    body    = request_body,
    query   = request_args,
    headers = {
      ["Content-Length"] = #(request_body or ""),
      ["Content-Type"]  = request_headers["Content-Type"],
      ["x-functions-key"] = config.apikey,
      ["x-functions-clientid"] = config.clientid,
    }
  }

  if not res then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local response_headers = res.headers
  local response_status = res.status
  local response_content = res:read_body()

  ok, err = client:set_keepalive(config.keepalive)
  if not ok then
    kong.log.err("could not keepalive connection: ", err)
  end

  return send(response_status, response_content, response_headers)
end


return azure
