local basic_serializer = require "kong.plugins.log-serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"
local http = require "resty.http"
local url = require "socket.url"

local string_format = string.format
local cjson_encode = cjson.encode

local HttpLogHandler = BasePlugin:extend()

HttpLogHandler.PRIORITY = 12
HttpLogHandler.VERSION = "0.1.0"

local HTTP = "http"
local HTTPS = "https"

-- Parse host url.
-- @param `url` host url
-- @return `parsed_url` a table with host details like domain name, port, path etc
local function parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == HTTP then
      parsed_url.port = 80
     elseif parsed_url.scheme == HTTPS then
      parsed_url.port = 443
     end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end
  if parsed_url.params then
    parsed_url.params = "?" .. parsed_url.params
  end
  return parsed_url
end

-- Log to a Http end point.
-- This basically is structured as a timer callback.
-- @param `premature` see openresty ngx.timer.at function
-- @param `conf` plugin configuration table, holds http endpoint details
-- @param `body` raw http body to be logged
-- @param `name` the plugin name (used for logging purposes in case of errors etc.)
local function log(premature, conf, body, name)
  if premature then
    return
  end
  name = "[" .. name .. "] "

  local headers
  local parsed_url = parse_url(conf.http_endpoint)

  if parsed_url.userinfo then
    -- for lua-resty-http client Authorization
    headers = {
      ["Content-Type"] = conf.content_type,
      ["Host"] = parsed_url.host,
      ["Authorization"] = string_format(
        "Basic %s", ngx.encode_base64(parsed_url.userinfo))
    }
  else
    headers = {
      ["Content-Type"] = conf.content_type,
      ["Host"] = parsed_url.host,
    }
  end

  local httpc = http.new()
  httpc:set_timeout(conf.timeout)
  local ok, err = httpc:connect(parsed_url.host, parsed_url.port)
  if not ok then
    ngx.log(ngx.ERR, name .. "request: " .. conf.http_endpoint .. " failed ", err)
    return
  end

  if parsed_url.scheme == HTTPS then
    local ok, err = httpc:ssl_handshake(nil, parsed_url.host, false)
    if not ok then
      ngx.log(ngx.ERR, name .. "request: " .. conf.http_endpoint .. " failed ", err)
      return
    end
  end

  local res
  res, err = httpc:request({
    path = parsed_url.path .. (parsed_url.params or ""),
    headers = headers,
    method = conf.method:upper(),
    body = body,
  })

  if not res then
    ngx.log(ngx.ERR, name .. "request: " .. conf.http_endpoint .. " failed ", err)
    return
  end

  if res.status >= 400 then
    ngx.log(ngx.ERR, name .. "request: " .. conf.http_endpoint .. " status_code: " .. tostring(res.status))
  end

  local reader = res.body_reader
  if reader then
    repeat
      local chunk, err = reader()
      if err then
        ngx.log(ngx.ERR, name .. "request: " .. conf.http_endpoint .. " failed ", err)
        return
      end
    until not chunk
  end

  if conf.keepalive then
    local ok, err = httpc:set_keepalive(conf.keepalive)
    if not ok then
      ngx.log(ngx.ERR, name .. "failed to set_keepalive ", err)
    end
  else
    local ok, err = httpc:close()
    if not ok then
      ngx.log(ngx.ERR, name .. "failed to close ", err)
    end
  end

end

-- Only provide `name` when deriving from this class. Not when initializing an instance.
function HttpLogHandler:new(name)
  HttpLogHandler.super.new(self, name or "http-log")
end

-- serializes context data into an html message body.
-- @param `ngx` The context table for the request being logged
-- @param `conf` plugin configuration table, holds http endpoint details
-- @return html body as string
function HttpLogHandler:serialize(ngx, conf)
  return cjson_encode(basic_serializer.serialize(ngx))
end

function HttpLogHandler:log(conf)
  HttpLogHandler.super.log(self)

  local ok, err = ngx.timer.at(0, log, conf, self:serialize(ngx, conf), self._name)
  if not ok then
    ngx.log(ngx.ERR, "[" .. self._name .. "] failed to create timer: ", err)
  end
end

return HttpLogHandler
