-- Sender object for using the Generic Logging Buffer.


local http = require "resty.http"


local sender = {}


local ngx_log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local WARN = ngx.WARN


local function log(lvl, ...)
  ngx_log(lvl, "[galileo] ", ...)
end


-- @return true if sent successfully
local function send(self, payload)

  local client = http.new()
  client:set_timeout(self.connection_timeout)

  local ok, err = client:connect(self.host, self.port)
  if not ok then
    log(ERR, "could not connect to Galileo collector: ", err)
    return false
  end

  if self.https then
    local ok, err = client:ssl_handshake(false, self.host, self.https_verify)
    if not ok then
      log(ERR, "could not perform SSL handshake with Galileo collector: ", err)
      return false
    end
  end

  local res, err = client:request {
    method = "POST",
    path = "/1.1.0/single",
    body = payload,
    headers = {
      ["Content-Type"] = "application/json"
    }
  }

  local success = true
  if not res then
    success = false
    log(ERR, "could not send ALF to Galileo collector: ", err)
  else
    local body = res:read_body()
    -- logging and error reports
    if res.status == 200 then
      log(DEBUG, "Galileo collector saved the ALF (200 OK): ", body)
    elseif res.status == 207 then
      log(DEBUG, "Galileo collector partially saved the ALF "
               .. "(207 Multi-Status): ", body)
    elseif res.status >= 400 and res.status < 500 then
      log(WARN, "Galileo collector refused this ALF (", res.status, "): ", body)
    elseif res.status >= 500 then
      success = false
      log(ERR, "Galileo collector HTTP error (", res.status, "): ", body)
    end
  end

  ok, err = client:set_keepalive()
  if ok ~= 1 then
    log(ERR, "could not keepalive Galileo collector connection: ", err)
  end

  return success
end


function sender.new(conf)
  if type(conf) ~= "table" then
    return nil, "arg #1 (conf) must be a table"
  elseif conf.connection_timeout ~= nil and type(conf.connection_timeout) ~= "number" then
    return nil, "connection_timeout must be a number"
  elseif type(conf.host) ~= "string" then
    return nil, "host must be a string"
  elseif type(conf.port) ~= "number" then
    return nil, "port must be a number"
  end

  local self = {
    host = conf.host,
    port = conf.port,
    https = conf.https,
    https_verify = conf.https_verify,
    connection_timeout  = conf.connection_timeout and conf.connection_timeout * 1000 or 30000, -- ms
    send = send,
  }

  return self
end


return sender
