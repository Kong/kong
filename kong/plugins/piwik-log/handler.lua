local basic_serializer = require "kong.plugins.log-serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"
local url = require "socket.url"

local PiwikLogHandler = BasePlugin:extend()

PiwikLogHandler.PRIORITY = 1

local HTTPS = "https"

-- Generates http payload .
-- @param `method` http method to be used to send data
-- @param `parsed_url` contains the host details
-- @param `message`  Message to be logged
-- @return `body` http payload
local function generate_post_payload(parsed_url, body, request_url, request_uri, referer, header, request_time)
--    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
--    method:upper(), parsed_url.path, parsed_url.host, string.len(body), body)
  math.randomseed(os.time())
  local lanuage = header["Accept-Language"]
  local uagent = header["User-Agent"]
  local random = math.random(1,10000)
  local cvar = "{'1':['req_size','" .. string.len(body) .. "']}"
  local path = parsed_url.path .. "?idsite=1&rec=1&url=" .. ngx.escape_uri(request_url) .. "&rand=" .. random .. "&action_name=" .. request_uri .. "&urlref=" .. referer .. "&ua=" .. uagent .. "&gt_ms=" .. request_time .. "&_cvar=" .. cvar
  ngx.log(ngx.NOTICE, "hallo test 123")
  return string.format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nAccept: */*\r\n\r\n",
    "GET", path, parsed_url.host )
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
-- @param `message`  Message to be logged
local function log(premature, conf, body, name, request_url, request_uri, referer, header, request_time)
  if premature then return end
  name = "["..name.."] "
  
  local ok, err
  local parsed_url = parse_url(conf.piwik_endpoint)
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

  ok, err = sock:send(generate_post_payload(parsed_url, body, request_url, request_uri, referer, header, request_time))
  if not ok then
    ngx.log(ngx.ERR, name.."failed to send data to "..host..":"..tostring(port)..": ", err)
  end

  ok, err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx.log(ngx.ERR, name.."failed to keepalive to "..host..":"..tostring(port)..": ", err)
    return
  end
end

-- Only provide `name` when deriving from this class. Not when initializing an instance.
function PiwikLogHandler:new(name)
  PiwikLogHandler.super.new(self, name or "piwik-log")
end

-- serializes context data into an html message body
-- @param `ngx` The context table for the request being logged
-- @return html body as string
function PiwikLogHandler:serialize(ngx)
  return cjson.encode(basic_serializer.serialize(ngx))
end
-- serializes context data into an html message body
-- @param `ngx` The context table for the request being logged
-- @return html body as string
function PiwikLogHandler:deserialize(ngx)
  return cjson.decode(basic_serializer.deserialize(ngx))
end

function PiwikLogHandler:log(conf)
  PiwikLogHandler.super.log(self)

  local request_url = ngx.var.host .. '/' .. ngx.var.uri
  local request_uri = ngx.var.uri
  local referer = ngx.decode_base64(ngx.unescape_uri( ngx.var.ref ))
  local header = ngx.req.get_headers()
  local request_time =  ngx.var.request_time
  local ok, err = ngx.timer.at(0, log, conf, self:serialize(ngx), self._name, request_url, request_uri, referer, header, request_time)
  if not ok then
    ngx.log(ngx.ERR, "["..self._name.."] failed to create timer: ", err)
  end
end

return PiwikLogHandler
