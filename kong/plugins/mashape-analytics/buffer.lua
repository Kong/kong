local alf_serializer = require "kong.plugins.mashape-analytics.alf"
local http = require "resty.http"

local setmetatable = setmetatable
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local remove = table.remove
local DEBUG = ngx.DEBUG
local WARN = ngx.WARN
local type = type
local huge = math.huge
local fmt = string.format
local ERR = ngx.ERR
local now = ngx.now

local _buffer_max_mb = 200
local _buffer_max_size = _buffer_max_mb * 2^20

local _M = {}

local _mt = {
  __index = _M
}

local function log(lvl, ...)
  ngx_log(lvl, fmt("[mashape-analytics] %s", fmt(...)))
end

local _delayed_flush, _send

local function _create_delayed_timer(self)
   local ok, err = timer_at(self.flush_timeout/1000, _delayed_flush, self)
   if not ok then
     log(ERR, "failed to create delayed flush timer: ", err)
   else
     self.timer_flush_pending = true
   end
end

local function _create_send_timer(self, to_send)
   local ok, err = timer_at(0, _send, self, to_send)
   if not ok then
     log(ERR, "failed to create send timer: ", err)
   else
     self.timer_send_pending = true
   end
end

-----------------
-- Timer handlers
-----------------

_delayed_flush = function(premature, self)
  if premature then return end

  if now() - self.last_t >= self.flush_timeout then
    _create_delayed_timer(self) -- flushing reported: we had activity
    return
  end

  -- no activity and timeout reached
  self:flush()
  self.timer_flush_pending = false
end

_send = function(premature, self, to_send)
  if premature then return end

  local retry -- retry this ALF if we encounter a failure here
              -- such as collector unresponsive

  local client = http.new()
  client:set_timeout(self.connection_timeout)

  local ok, err = client:connect(self.host, self.port)
  if not ok then
    retry = true
    log(ERR, "could not connect to Galileo collector: ", err)
  else
    local res, err = client:request {
      method = "POST",
      path = "/1.1.0/single",
      body = to_send.payload,
      headers = {
        ["Content-Type"] = "application/json"
      }
    }
    if not res then
      retry = true
      log(ERR, "could not send batch to Galileo collector: ", err)
    elseif res.status == 200 then
      log(DEBUG, "Galileo collector saved the ALF")
    elseif res.status == 207 then
      log(DEBUG, "Galileo collector saved parts the ALF")
    elseif res.status >= 400 and res.status < 500 then
      log(ERR, "Galileo collector refused this ALF")
    elseif res.status >= 500 then
      retry = true
      log(ERR, "Galileo collector error")
    end

    if not res or res.headers["connection"] == "close" then
      client:close()
    else
      client:set_keepalive()
    end
  end

  if retry then
    to_send.retries = to_send.retries + 1
    if to_send.retries < self.retry_count then
      -- add our ALF back to the sending queue, but at the
      -- end of it.
      self.sending_queue[#self.sending_queue+1] = to_send
    else
      log(WARN, "ALF was already tried %d times, dropping it", to_send.retries-1)
    end
  else -- ALF was sent or discarded
    self.sending_queue_size = self.sending_queue_size - #to_send.payload
  end

  if #self.sending_queue > 0 then -- more to send?
    -- pop the oldest from the sending_queue
    _create_send_timer(self, remove(self.sending_queue, 1))
  else
    -- we finished flushing the sending_queue, allow the creation
    -- of a future timer once the current ALF reached its limit
    -- and we trigger a flush()
    self.timer_send_pending = false
  end
end

---------
-- Buffer
---------

function _M.new(conf)
  if type(conf) ~= "table" then
    return nil, "arg #1 (conf) must be a table"
  elseif type(conf.service_token) ~= "string" then
    return nil, "service_token must be a string"
  elseif conf.environment ~= nil and type(conf.environment) ~= "string" then
    return nil, "environment must be a string"
  elseif conf.log_bodies ~= nil and type (conf.log_bodies) ~= "boolean" then
    return nil, "log_bodies must be a boolean"
  elseif conf.retry_count ~= nil and type(conf.retry_count) ~= "number" then
    return nil, "retry_count must be a number"
  elseif conf.connection_timeout ~= nil and type(conf.connection_timeout) ~= "number" then
    return nil, "connection_timeout must be a number"
  elseif conf.flush_timeout ~= nil and type(conf.flush_timeout) ~= "number" then
    return nil, "flush_timeout must be a number"
  elseif conf.queue_size ~= nil and type(conf.queue_size) ~= "number" then
    return nil, "queue_size must be a number"
  elseif type(conf.host) ~= "string" then
    return nil, "host must be a string"
  elseif type(conf.port) ~= "number" then
    return nil, "port must be a number"
  end

  local buffer = {
    service_token       = conf.service_token,
    environment         = conf.environment,
    host                = conf.host,
    port                = conf.port,
    log_bodies          = conf.log_bodies or false,
    retry_count         = conf.retry_count or 0,
    connection_timeout  = conf.connection_timeout and conf.connection_timeout * 1000 or 30000, -- ms
    flush_timeout       = conf.flush_timeout and conf.flush_timeout * 1000 or 2000,      -- ms
    queue_size          = conf.queue_size or 1000,
    cur_alf             = alf_serializer.new(conf.log_bodies),
    sending_queue       = {},                             -- FILO queue
    sending_queue_size  = 0,
    last_t              = huge,
    timer_flush_pending = false,
    timer_send_pending  = false
  }

  return setmetatable(buffer, _mt)
end

function _M:add_entry(...)
  local ok, err = self.cur_alf:add_entry(...)
  if not ok then
    log(ERR, "could not add entry to ALF: ", err)
    return ok, err
  end

  local t = now()

  if t - self.last_t >= self.flush_timeout
     or err >= self.queue_size then -- err is the queue size in this case

     ok, err = self:flush()
     if not ok then return nil, err end -- for our tests only

   elseif not self.timer_flush_pending then -- start delayed timer if none
     _create_delayed_timer(self)
   end

  self.last_t = t

  return true
end

function _M:flush()
  local alf_json, err = self.cur_alf:serialize(self.service_token, self.environment)

  self.cur_alf:reset()

  if not alf_json then
    log(ERR, "could not serialize ALF: ", err)
    return nil, err
  elseif self.sending_queue_size + #alf_json > _buffer_max_size then
    log(WARN, "buffer is full, discarding this ALF")
    return nil, "buffer full"
  end

  self.sending_queue_size = self.sending_queue_size + #alf_json
  self.sending_queue[#self.sending_queue+1] = {
    payload = alf_json,
    retries = 0
  }

  -- let's try to send. we might be sending an older ALF with
  -- this call, but that is fine, because as long as the sending_queue
  -- has elements, 'send()' will keep trying to flush it.
  self:send()

  return true
end

function _M:send()
  if #self.sending_queue < 1 then
    return nil, "empty queue"
  end

  -- only allow a single pending timer to send ALFs at a time
  -- this timer will keep calling itself while it has payloads
  -- to send.
  if not self.timer_send_pending then
    -- pop the oldest ALF from the queue
    _create_send_timer(self, remove(self.sending_queue, 1))
  end
end

return _M
