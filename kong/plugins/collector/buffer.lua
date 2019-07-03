-- ALF Buffer.
-- Keeps an ALF serializer in memory. When that serializer is full, flushes
-- its serialized (JSON encoded) ALF into a sending queue (FILO). The
-- sending_queue cannot exceed a given size, to avoid side effects on the
-- LuaJIT VM. If the sending_queue is full, the data is discarded.
-- If no entries have been added to the ALF serializer in the last 'N'
-- seconds (configurable), the ALF is flushed regardless if full or not,
-- and also queued for sending.
--
-- Once the sending_queue has elements, it tries to send the oldest one to
-- the Brain collector in a timer (to be called from log_by_lua). That
-- timer will keep calling itself as long as the sending_queue isn't empty.
--
-- If an ALF could not be sent, it can be tried again later (depending on the
-- error). If so, it is added back at the end of the sending queue. An ALF
-- can only be tried 'N' times, afterwards it is discarded.
--
-- Each nginx worker gets its own retry delays, stored at the chunk level of
-- this module. When the collector cannot be reached, the retry delay is
-- increased by n_try^2, up to 60s.

local alf_serializer = require "kong.plugins.collector.alf"
local http = require "resty.http"

local setmetatable = setmetatable
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local remove = table.remove
local type = type
local huge = math.huge
local fmt = string.format
local min = math.min
local pow = math.pow
local now = ngx.now
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local WARN = ngx.WARN

local _buffer_max_mb = 200
local _buffer_max_size = _buffer_max_mb * 2^20

-- per-worker retry policy
-- simply increment the delay by n_try^2
-- max delay of 60s
local retry_delay_idx = 1
local _retry_max_delay = 60

local _M = {}

local _mt = {
  __index = _M
}

local function get_now()
  return now()*1000
end

local function log(lvl, ...)
  ngx_log(lvl, "[collector] ", ...)
end

local _delayed_flush, _send

local function _create_delayed_timer(self)
   local ok, err = timer_at(self.flush_timeout/1000, _delayed_flush, self)
   if not ok then
      log(ERR, "failed to create delayed flush timer: ", err)
   else
      --log(DEBUG, "delayed timer created")
      self.timer_flush_pending = true
   end
end

local function _create_send_timer(self, to_send, delay)
   delay = delay or 1
   local ok, err = timer_at(delay, _send, self, to_send)
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
  if premature then return
  elseif get_now() - self.last_t < self.flush_timeout then
    -- flushing reported: we had activity
    log(DEBUG, "[delayed flushing handler] buffer had activity, ",
               "delaying flush")
    _create_delayed_timer(self)
  else
    -- no activity and timeout reached
    log(DEBUG, "[delayed flushing handler] buffer had no activity, flushing ",
               "triggered by flush_timeout")
    self:flush()
    self.timer_flush_pending = false
  end
end

_send = function(premature, self, to_send)
  if premature then
    return
  end

  -- retry trigger, in case the collector
  -- is unresponseive
  local retry

  local client = http.new()
  client:set_timeout(self.connection_timeout)

  local ok, err = client:connect(self.host, self.port)
  if not ok then
    retry = true
    log(ERR, "could not connect to collector: ", err)
  else
    if self.https then
      local ok, err = client:ssl_handshake(false, self.host, self.https_verify)
      if not ok then
        log(ERR, "could not perform SSL handshake with Brain collector: ", err)
        return
      end
    end

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
      log(ERR, "could not send ALF to Brain collector: ", err)
    else
      local body = res:read_body()
      -- logging and error reports
      if res.status == 200 then
        log(DEBUG, "Brain collector saved the ALF (200 OK): ", body)
      elseif res.status == 207 then
        log(DEBUG, "Brain collector partially saved the ALF "
                 .. "(207 Multi-Status): ", body)
      elseif res.status >= 400 and res.status < 500 then
        log(WARN, "Brain collector refused this ALF (", res.status, "): ", body)
      elseif res.status >= 500 then
        retry = true
        log(ERR, "Brain collector HTTP error (", res.status, "): ", body)
      end
    end

    local ok, err = client:set_keepalive()
    if ok ~= 1 then
      log(ERR, "could not keepalive Brain collector connection: ", err)
    end
  end

  local next_retry_delay = 1

  if retry then
    -- collector could not be reached, must retry
    retry_delay_idx = retry_delay_idx + 1
    next_retry_delay = min(_retry_max_delay, pow(retry_delay_idx, 2))

    log(WARN, "could not reach Brain collector, retrying in: ", next_retry_delay)

    to_send.retries = to_send.retries + 1
    if to_send.retries < self.retry_count then
      -- add our ALF back to the sending queue, but at the
      -- end of it.
      self.sending_queue[#self.sending_queue+1] = to_send
    else
      log(WARN, fmt("ALF was already tried %d times, dropping it", to_send.retries))
    end
  else
    -- Success!
    -- ALF was sent or discarded
    retry_delay_idx = 1 -- reset our retry policy
    self.sending_queue_size = self.sending_queue_size - #to_send.payload
  end

  if #self.sending_queue > 0 then -- more to send?
    -- pop the oldest from the sending_queue
    log(DEBUG, fmt("sending oldest ALF, %d still queued", #self.sending_queue-1))
    _create_send_timer(self, remove(self.sending_queue, 1), next_retry_delay)
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
  elseif type(conf.server_addr) ~= "string" then
    return nil, "server_addr must be a string"
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
    https               = conf.https,
    https_verify        = conf.https_verify,
    log_bodies          = conf.log_bodies or false,
    retry_count         = conf.retry_count or 0,
    connection_timeout  = conf.connection_timeout and conf.connection_timeout * 1000 or 30000, -- ms
    flush_timeout       = conf.flush_timeout and conf.flush_timeout * 1000 or 2000,            -- ms
    queue_size          = conf.queue_size or 1000,
    cur_alf             = alf_serializer.new(conf.log_bodies, conf.server_addr),
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

  if err >= self.queue_size then -- err is the queue size in this case
     ok, err = self:flush()
     if not ok then
       -- for our tests only
       return nil, err
     end
   elseif not self.timer_flush_pending then -- start delayed timer if none
     _create_delayed_timer(self)
   end

  self.last_t = get_now()

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

  log(DEBUG, "flushing ALF for sending (", err, " entries)")

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
    log(DEBUG, fmt("sending oldest ALF, %d still queued", #self.sending_queue-1))
    _create_send_timer(self, remove(self.sending_queue, 1))
  end
end

return _M
