local Queue = require "kong.tools.queue"
local cjson = require "cjson"
local url = require "socket.url"
local http = require "resty.http"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"

local kong = kong
local ngx = ngx
local encode_base64 = ngx.encode_base64
local tostring = tostring
local tonumber = tonumber
local fmt = string.format
local pairs = pairs
local max = math.max

-- Parse host url.
local function parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
    elseif parsed_url.scheme == "https" then
      parsed_url.port = 443
    end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end
  return parsed_url
end

-- Sends the provided entries to the configured plugin host
local function send_entries(conf, entries)
  local content_length = #entries[1]
  local payload = entries[1]
  
  local method = conf.method
  local timeout = conf.timeout
  local keepalive = conf.keepalive
  local content_type = conf.content_type
  local http_endpoint = conf.http_endpoint

  local parsed_url = parse_url(http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)
  local userinfo = parsed_url.userinfo

  local httpc = http.new()
  httpc:set_timeout(timeout)

  local headers = {
    ["Content-Type"] = content_type,
    ["Content-Length"] = content_length,
    ["Authorization"] = userinfo and "Basic " .. encode_base64(userinfo) or nil
  }
  if conf.headers then
    for h, v in pairs(conf.headers) do
      headers[h] = headers[h] or v -- don't override Host, Content-Type, Content-Length, Authorization
    end
  end

  local log_server_url = fmt("%s://%s:%d%s", parsed_url.scheme, host, port, parsed_url.path)

  local res, err = httpc:request_uri(log_server_url, {
    method = method,
    headers = headers,
    body = payload,
    keepalive_timeout = keepalive,
    ssl_verify = false,
  })
  if not res then
    return nil, "failed request to " .. host .. ":" .. tostring(port) .. ": " .. err
  end

  -- always read response body, even if we discard it without using it on success
  local response_body = res.body

  kong.log.debug(fmt("http-logger sent data log server, %s:%s HTTP status %d",
    host, port, res.status))

  if res.status < 300 then
    return true
  else
    return nil, "request to " .. host .. ":" .. tostring(port)
      .. " returned status code " .. tostring(res.status) .. " and body "
      .. response_body
  end
end

local HttpLoggerHandler = {
  PRIORITY = 12,
  VERSION = kong_meta.version,
}

-- Create a queue name from configuration parameters
local function make_queue_name(conf)
  return fmt("%s:%s:%s:%s:%s",
    conf.http_endpoint,
    conf.method,
    conf.content_type,
    conf.timeout,
    conf.keepalive)
end

function HttpLoggerHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression)())
    end
  end

  local queue_conf = Queue.get_plugin_params("http-logger", conf, make_queue_name(conf))
  kong.log.debug("Queue name automatically configured based on configuration parameters to: ", queue_conf.name)

  local ok, err = Queue.enqueue(
    queue_conf,
    send_entries,
    conf,
    cjson.encode(kong.log.serialize())
  )
  if not ok then
    kong.log.err("Failed to enqueue log entry to log server: ", err)
  end
end

return HttpLoggerHandler
