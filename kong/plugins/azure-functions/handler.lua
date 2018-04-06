local BasePlugin    = require "kong.plugins.base_plugin"
local responses     = require "kong.tools.responses"
local meta          = require "kong.meta"
local http          = require "resty.http"

local pairs         = pairs
local get_body_data = ngx.req.get_body_data
local get_uri_args  = ngx.req.get_uri_args
local get_headers   = ngx.req.get_headers
local read_body     = ngx.req.read_body
local get_method    = ngx.req.get_method
local ngx_print     = ngx.print
local ngx_exit      = ngx.exit
local ngx_log       = ngx.log
local response_headers = ngx.header
local var           = ngx.var


local SERVER        = meta._NAME .. "/" .. meta._VERSION
local conf_cache    = setmetatable({}, { __mode = "k" })


local azure = BasePlugin:extend()

azure.PRIORITY = 749
azure.VERSION = "0.1.0"


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
  local request_method = get_method()
  read_body()
  local request_body = get_body_data()
  local request_headers = get_headers()
  local request_args = get_uri_args()

  client:set_timeout(config.timeout)

  local ok, err = client:connect(config.host, config.port)
  if not ok then
    ngx_log(ngx.ERR, "[azure-functions] could not connect to Azure service: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if config.https then
    local ok, err = client:ssl_handshake(false, config.host, config.https_verify)
    if not ok then
      ngx_log(ngx.ERR, "[azure-functions] could not perform SSL handshake : ", err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end

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
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  -- prepare response for downstream
  for k, v in pairs(res.headers) do
    response_headers[k] = v
  end

  response_headers.Server = SERVER
  ngx.status = res.status
  local response_body = res:read_body()
  ngx_print(response_body)

  ok, err = client:set_keepalive(config.keepalive)
  if not ok then
    ngx_log(ngx.ERR, "[azure-functions] could not keepalive connection: ", err)
  end

  return ngx_exit(res.status)
end


return azure
