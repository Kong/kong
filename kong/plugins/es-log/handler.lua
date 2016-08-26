local basic_serializer = require "kong.plugins.log-serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"
local url = require "socket.url"
local os = require "os"

local read_body = ngx.req.read_body
local get_body_data = ngx.req.get_body_data

local _server_addr

local ESLogHandler = BasePlugin:extend()

ESLogHandler.PRIORITY = 1

local HTTPS = "https"

-- Generates http payload .
-- @param `method` http method to be used to send data
-- @param `parsed_url` contains the host details
-- @param `message`  Message to be logged
-- @return `body` http payload
local function generate_post_payload(method, parsed_url, body)
  return string.format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
    method:upper(), parsed_url.path, parsed_url.host, string.len(body), body)
end

-- Parse host url
-- @param `url`  host url
-- @return `parsed_url`  a table with host details like domain name, port, path etc
local function parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
     elseif parsed_url.scheme == HTTPS then
      parsed_url.port = 443
     end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end
  return parsed_url
end

-- Log to a Http end point.
-- @param `premature`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `body`  Message to be logged
local function log(premature, conf, body, name)
  if premature then return end
  name = "["..name.."] "
  
  local ok, err
  local parsed_url = parse_url(conf.es_url)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)

  local sock = ngx.socket.tcp()
  sock:settimeout(conf.timeout)

  ok, err = sock:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, name.."failed to connect to "..host..":"..tostring(port)..": ", err)
    return
  end

  if parsed_url.scheme == HTTPS then
    local _, err = sock:sslhandshake(true, host, false)
    if err then
      ngx.log(ngx.ERR, name.."failed to do SSL handshake with "..host..":"..tostring(port)..": ", err)
    end
  end

  local dateStr = os.date("%Y.%m.%d")
  
  parsed_url.path = parsed_url.path .. conf.index_prefix .. dateStr .. '/' .. conf.index_type

  ok, err = sock:send(generate_post_payload("POST", parsed_url,  body))
  if not ok then
    ngx.log(ngx.ERR, name.."failed to send data to "..host..":"..tostring(port)..parsed_url.path..": ", err)
  end

  ok, err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx.log(ngx.ERR, name.."failed to keepalive to "..host..":"..tostring(port)..": ", err)
    return
  end
end

function ESLogHandler:access(conf)
  ESLogHandler.super.access(self)

  if not _server_addr then
    _server_addr = ngx.var.server_addr
  end

  if conf.log_bodies then
    read_body()
    ngx.ctx.galileo = {req_body = get_body_data()}
  end
end

-- Only provide `name` when deriving from this class. Not when initializing an instance.
function ESLogHandler:new(name)
  ESLogHandler.super.new(self, name or "es-log")
end

-- serializes context data into an html message body
-- @param `ngx` The context table for the request being logged
-- @return html body as string
function ESLogHandler:serialize(ngx)
  local logModel = basic_serializer.serialize(ngx)
  logModel.server_address = _server_addr
  logModel.timestamp = ngx.time()
  local ctx = ngx.ctx
  if ctx.galileo then
    logModel.bodies = {
      req = ctx.galileo.req_body,
      res = ctx.galileo.res_body
    } 
  end
  return cjson.encode(logModel)
end

function ESLogHandler:body_filter(conf)
  ESLogHandler.super.body_filter(self)

  if conf.log_bodies then
    local chunk = ngx.arg[1]
    local ctx = ngx.ctx
    local res_body = ctx.galileo and ctx.galileo.res_body or ""
    res_body = res_body .. (chunk or "")
    ctx.galileo.res_body = res_body
  end
end

function ESLogHandler:log(conf)
  ESLogHandler.super.log(self)

  local ok, err = ngx.timer.at(0, log, conf, self:serialize(ngx), self._name)
  if not ok then
    ngx.log(ngx.ERR, "["..self._name.."] failed to create timer: ", err)
  end
end

return ESLogHandler
