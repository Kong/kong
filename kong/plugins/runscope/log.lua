local cjson = require "cjson"
local url = require "socket.url"

local _M = {}

local HTTPS = "https"
local ngx_log = ngx.log
local ngx_log_ERR = ngx.ERR
local ngx_timer_at = ngx.timer.at
local string_format = string.format
local string_len = string.len

-- Generates http payload .
-- @param `method` http method to be used to send data
-- @param `parsed_url` contains the host details
-- @param `message`  Message to be logged
-- @return `payload` http payload
local function generate_post_payload(parsed_url, access_token, message)
  local body = cjson.encode(message)
  local payload = string_format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
    "POST", parsed_url.path, parsed_url.host, access_token, string_len(body), body)
  return payload
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
local function log(premature, conf, message)
  if premature then
    return
  end

  local ok, err
  local parsed_url = parse_url(conf.api_endpoint.."/buckets/"..conf.bucket_key.."/messages")
  local access_token = conf.access_token
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)

  local sock = ngx.socket.tcp()
  sock:settimeout(conf.timeout)

  ok, err = sock:connect(host, port)
  if not ok then
    ngx_log(ngx_log_ERR, "[runscope] failed to connect to "..host..":"..tostring(port)..": ", err)
    return
  end

  if parsed_url.scheme == HTTPS then
    local _, err = sock:sslhandshake(true, host, false)
    if err then
      ngx_log(ngx_log_ERR, "[runscope] failed to do SSL handshake with "..host..":"..tostring(port)..": ", err)
    end
  end

  ok, err = sock:send(generate_post_payload(parsed_url, access_token, message).."\r\n")
  if not ok then
    ngx_log(ngx_log_ERR, "[runscope] failed to send data to "..host..":"..tostring(port)..": ", err)
  end

  ok, err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx_log(ngx_log_ERR, "[runscope] failed to keepalive to "..host..":"..tostring(port)..": ", err)
    return
  end
end

function _M.execute(conf, message)
  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(ngx_log_ERR, "[runscope] failed to create timer: ", err)
  end
end

return _M
