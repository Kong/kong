local cjson = require "cjson"
local url = require "socket.url"

local _M = {}

-- Generates http payload .
-- @param `method` http method to be used to send data
-- @param `parsed_url` contains the host details     
-- @param `message`  Message to be logged
-- @return `payload` http payload
local function generate_post_payload(method, parsed_url, message)
  local body = cjson.encode(message);
  local payload = string.format("%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s", 
    method:upper(), parsed_url.path, parsed_url.host, string.len(body), body)
  return payload
end

-- Parse host url  .
-- @param `url`  host url     
-- @return a table with host details like domain name, port, path etc
local function parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then 
      parsed_url.port = 80
     elseif parsed_url.scheme == "https" then
      parsed_url.port = 443
     end
  end
  return parsed_url
end

-- Log to a Http end point.
-- @param `premature` 
-- @param `conf`     Configuration table, holds http endpoint details 
-- @param `message`  Message to be logged
local function log(premature, conf, message)
  local ok, err
  local parsed_url = parse_url(conf.http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)
  
  local sock = ngx.socket.tcp()
  sock:settimeout(conf.timeout)

  ok, err = sock:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, "failed to connect to "..host..":"..tostring(port)..": ", err)
    return
  end

  ok, err = sock:send(generate_post_payload(conf.method, parsed_url, message).."\r\n")
  if not ok then
    ngx.log(ngx.ERR, "failed to send data to "..host..":"..tostring(port)..": ", err)
  end

  ok, err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx.log(ngx.ERR, "failed to keepalive to "..host..":"..tostring(port)..": ", err)
    return
  end
end

function _M.execute(conf)
  local ok, err = ngx.timer.at(0, log, conf, ngx.ctx.log_message)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
