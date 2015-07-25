-- ALF buffer module
-- This module contains a buffered array of ALF objects to be sent to the upstream
-- Mashape Analytics socket server.

local json = require "cjson"
local http = require "resty_http"

local EMPTY_ARRAY_PLACEHOLDER = "__empty_array_placeholder__"
local ANALYTICS_SOCKET = {
  host = "socket.analytics.mashape.com",
  port = 80,
  path = "/1.0.0/batch"
}

local buffer_mt = {}
buffer_mt.__index = buffer_mt

function buffer_mt:add_alf(alf)
  table.insert(self.alfs, alf)
  return table.getn(self.alfs)
end

function buffer_mt:to_json_string()
  local str = json.encode(self.to_send)
  return str:gsub("\""..EMPTY_ARRAY_PLACEHOLDER.."\"", ""):gsub("\\/", "/")
end

function buffer_mt:flush_entries()
  for _, alf in ipairs(self.alfs) do
    table.insert(self.to_send, alf)
  end

  self.alfs = {}
end

function buffer_mt.new()
  local buffer = {
    alfs = {},
    sending = false,
    delayed = false,
    latest_call = nil, -- stub
    to_send = {}
  }
  return setmetatable(buffer, buffer_mt)
end

function buffer_mt.send_batch(premature, self)
  if self.sending then return end
  self.sending = true -- simple lock

  -- Put ALFs in `to_send`
  self:flush_entries()
  if table.getn(self.to_send) < 1 then
    return
  end

  local message = self:to_json_string()

  local ok, err
  local batch_saved = false
  local client = http:new()
  client:set_timeout(50000) -- 5 sec

  ok, err = client:connect(ANALYTICS_SOCKET.host, ANALYTICS_SOCKET.port)
  if ok then
    local res, err = client:request({path = ANALYTICS_SOCKET.path, body = message})
    if not res then
      ngx.log(ngx.ERR, "[mashape-analytics] failed to send batch: "..err)
    elseif res.status == 200 then
      batch_saved = true
      ngx.log(ngx.DEBUG, string.format("[mashape-analytics] successfully saved the batch. (%s)", res.body))
    else
      ngx.log(ngx.ERR, string.format("[mashape-analytics] socket server refused the batch. Status: (%s) Error: (%s)", res.status, res.body))
    end

    -- close connection, or put it into the connection pool
    if not res or res.headers["connection"] == "close" then
      ok, err = client:close()
      if not ok then
        ngx.log(ngx.ERR, "[mashape-analytics] failed to close socket: "..err)
      end
    else
      client:set_keepalive()
    end
  else
    ngx.log(ngx.ERR, "[mashape-analytics] failed to connect to the socket server: "..err)
  end

  if batch_saved then
    self.to_send = {}
  else
    local ok, err = ngx.timer.at(0, self.send_batch, self)
    if not ok then
      ngx.log(ngx.ERR, "[mashape-analytics] failed to create batch retry timer: ", err)
    end
  end

  self.sending = false
end

return buffer_mt
