local influxdb_serializer = require "kong.plugins.log-serializers.influxdb"
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"
local url = require "socket.url"

local InfluxdbLogHandler = BasePlugin:extend()

InfluxdbLogHandler.PRIORITY = 1

local HTTPS = "https"

-- influxdb util function
-- ref:https://docs.influxdata.com/influxdb/v0.13/write_protocols/write_syntax/

local function influxdb_escape(str)
    if type(str) ~= "string" then
        return str
    end

    return string.gsub(str, "[=, ]", function (w) return "\\"..w end)

end

-- Generates influxdb line
-- @param `measurement`, similar to MySQL table name
-- @param `message`  Message to be logged
-- @return `line` of influxdb line protocol
local function generate_influxdb_line(measurement, message)
    local line = measurement
    local flag = true

    if message.tag then
        -- Tags should be sorted by key before being sent for best performance
        -- ref: https://docs.influxdata.com/influxdb/v0.13/write_protocols/line/
        local key_table = {}
        for k, _ in pairs(message.tag) do
            table.insert(key_table, k)
        end
        table.sort(key_table)
        for _, k in ipairs(key_table) do
            v = message.tag[k]
            line = line..","
            if type(v) == "table" then
                v = cjson.encode(v)
            end
            line = line..k.."="..influxdb_escape(v)
        end
    end

    if message.field then
        for k, v in pairs(message.field) do
            if flag then
                line = line.." "
                flag = false
            else
                line = line..","
            end
            line = line..k.."="..v
        end
    end

    return line
end

-- influx util function end

-- Generates http payload .
-- @param `method` http method to be used to send data
-- @param `parsed_url` contains the host details
-- @param `message`  Message to be logged
-- @return `body` http payload
local function generate_post_payload(method, parsed_url, body)
  return string.format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: %s\r\n\r\n%s",
    method:upper(), parsed_url.path.."?"..parsed_url.query, parsed_url.host, string.len(body), body)
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
  if not parsed_url.query then
    parsed_url.query = ""
  end
  return parsed_url
end

-- Log to a Http end point.
-- @param `premature`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(premature, conf, body, name)
  if premature then return end
  name = "["..name.."] "

  local ok, err
  local parsed_url = parse_url(conf.http_endpoint)
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

  ok, err = sock:send(generate_post_payload(conf.method, parsed_url, body))
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
function InfluxdbLogHandler:new(name)
  InfluxdbLogHandler.super.new(self, name or "influxdb-log")
end

-- serializes context data into an influxdb-line-protocol body
-- @param `ngx` The context table for the request being logged
-- @return html body as string
function InfluxdbLogHandler:serialize(ngx)
  return generate_influxdb_line("kong", influxdb_serializer.serialize(ngx))
end

function InfluxdbLogHandler:log(conf)
  InfluxdbLogHandler.super.log(self)

  local ok, err = ngx.timer.at(0, log, conf, self:serialize(ngx), self._name)
  if not ok then
    ngx.log(ngx.ERR, "["..self._name.."] failed to create timer: ", err)
  end
end

return InfluxdbLogHandler
