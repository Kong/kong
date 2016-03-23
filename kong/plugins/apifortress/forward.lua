-- ©2016 API Fortress Inc.
-- Forwards the data to the configured API Fortress engine
local bit = require "bit"
local cjson = require "cjson"
local basic_serializer = require "kong.plugins.log-serializers.basic"
local serializer = require "kong.plugins.apifortress.fortress_serializer"
local url = require "socket.url"

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

local function generate_post_payload(parsed_url, key, token, message)
  local body = cjson.encode(message)
  local payload = string.format(
    "%s %s?%s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nContent-Type: application/json\r\nX-Key: %s\r\nX-Token: %s\r\nContent-Length: %s\r\n\r\n%s",
    "POST", parsed_url.path, parsed_url.query, parsed_url.host, key, token, string.len(body), body)
  return payload
end

local function genToken(conf)
  local timestamp = tostring(os.time())
  local baseString = conf.apikey..conf.secret..timestamp
  return ngx.md5(baseString)
end

local function send(self,conf,message)
  local ok, err
  local token = genToken(conf)
  local key = conf.apikey
  local url = conf.endpoint
  if not string.ends(url,"/") then
    url = url.."/"
  end
  local url = parse_url(url..conf.projectId.."?mode=serializer")

  local host = url.host
  local port = tonumber(url.port)

  local sock = ngx.socket.tcp()
  sock:settimeout(2000)
  ok, err = sock:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, "[apifortress-plugin] failed to connect to "..host..":"..tostring(port)..": ", err)
    return
  end

  if url.scheme == HTTPS then
    local _, err = sock:sslhandshake(true, host, false)
    if err then
      ngx.log(ngx.ERR, "[apifortress-plugin] failed to do SSL handshake with "..host..":"..tostring(port)..": ", err)
    end
  end

  ok, err = sock:send(generate_post_payload(url,key,token,message).."\r\n")
  if not ok then
    ngx.log(ngx.ERR, "[apifortress-plugin] failed to send data to "..host..":"..tostring(port)..": ", err)
  end
  ok, err = sock:setkeepalive(100)
  if not ok then
    ngx.log(ngx.ERR, "[apifortress-plugin] failed to keepalive to "..host..":"..tostring(port)..": ", err)
    return
  end
end

local _M = {}


function _M.execute(conf)
  local message = serializer.serialize(ngx)
  local pluginContextName = ngx.ctx.api.name.."apifortress"
  if not ngx[pluginContextName] then
    ngx[pluginContextName] = { currentThreshold = 0 }
  end
  ngx[pluginContextName].currentThreshold = ngx[pluginContextName].currentThreshold+1
  if (ngx[pluginContextName].currentThreshold % conf.threshold) == 0 then
    local ok, err = ngx.timer.at(0, send, conf, message)
    if not ok then
      ngx.log(ngx.ERR, "[apifortress-plugin] failed to create timer: ", err)
    end
  end
end

return _M
