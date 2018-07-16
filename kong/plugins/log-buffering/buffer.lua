-- Generic Logging Buffer.
--
-- Requires two objects for its use: a producer and a sender.
--
-- The producer needs to provide the following interface:
-- * `ok, size_or_err = producer:add_entry(...)`
-- * `produced, count_or_err, bytes = producer:produce()`
-- * `producer:flush()`
--
-- The sender needs to provide the following interface:
-- * `ok = sender:send(produced)`
--
-- When the producer is full, the buffer flushes
-- its produced data into a sending queue (FILO). The
-- sending_queue cannot exceed a given size, to avoid side effects on the
-- LuaJIT VM. If the sending_queue is full, the data is discarded.
-- If no entries have been added to the producer in the last 'N'
-- seconds (configurable), it is flushed regardless if full or not,
-- and also queued for sending.
--
-- Once the sending_queue has elements, it tries to send the oldest one to
-- using the sender in a timer (to be called from log_by_lua). That
-- timer will keep calling itself as long as the sending_queue isn't empty.
--
-- If the data could not be sent, it can be tried again later (depending on the
-- error). If so, it is added back at the end of the sending queue. Data
-- can only be tried 'N' times, afterwards it is discarded.
--
-- Each nginx worker gets its own retry delays, stored at the chunk level of
-- this module. If the sender fails sending, the retry delay is
-- increased by n_try^2, up to 60s.


local setmetatable = setmetatable
local timer_at = ngx.timer.at
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


local BUFFER_MAX_SIZE_MB = 200
local BUFFER_MAX_SIZE_BYTES = BUFFER_MAX_SIZE_MB * 2^20


-- per-worker retry policy
-- simply increment the delay by n_try^2
local retry_delays = {}


-- max delay of 60s
local RETRY_MAX_DELAY = 60


local Buffer = {}


local Buffer_mt = {
  __index = Buffer
}


-- Forward function declarations
local delayed_flush
local run_sender


-------------------------------------------------------------------------------
-- Create a timer for the `delayed_flush` operation.
-- @param self Buffer
local function schedule_delayed_flush(self)
  local ok, err = timer_at(self.flush_timeout/1000, delayed_flush, self)
  if not ok then
    self.log(ERR, "failed to create delayed flush timer: ", err)
    return
  end
  --log(DEBUG, "delayed timer created")
  self.timer_flush_pending = true
end


-------------------------------------------------------------------------------
-- Create a timer for the `run_sender` operation.
-- @param self Buffer
-- @param to_send table: package to be sent, including `bytes` count,
-- `payload` data and `retries` counter.
-- @param delay number: timer delay in seconds
local function schedule_run_sender(self, to_send, delay)
  delay = delay or 1
  local ok, err = timer_at(delay, run_sender, self, to_send)
  if not ok then
    self.log(ERR, "failed to create send timer: ", err)
    return
  end
  self.timer_send_pending = true
end

-----------------
-- Timer handlers
-----------------


-------------------------------------------------------------------------------
-- Get the current time.
-- @return current time in seconds
local function get_now()
  return now()*1000
end


-------------------------------------------------------------------------------
-- Timer callback for triggering a buffer flush.
-- @param premature boolean: ngx.timer premature indicator
-- @param self Buffer
-- @return nothing
delayed_flush = function(premature, self)
  if premature then
    return
  end

  if get_now() - self.last_t < self.flush_timeout then
    -- flushing reported: we had activity
    self.log(DEBUG, "[delayed flush handler] buffer had activity, ",
               "delaying flush")
    schedule_delayed_flush(self)
    return
  end

  -- no activity and timeout reached
  self.log(DEBUG, "[delayed flush handler] buffer had no activity, flushing ",
             "triggered by flush_timeout")
  self:flush()
  self.timer_flush_pending = false
end


-------------------------------------------------------------------------------
-- Adjust the Timer callback for triggering a buffer flush.
-- @param premature boolean: ngx.timer premature indicator
-- @param to_send table: package to be sent, including `bytes` count,
-- `payload` data and `retries` counter.
-- @param self table: Buffer object.
-- @return number: next retry delay to be used, in seconds.
local function adjust_retries(self, to_send, was_sent)
  if was_sent then
    -- Success!
    -- data was sent or discarded
    retry_delays[self.id] = 1 -- reset our retry policy
    self.sending_queue_size = self.sending_queue_size - to_send.bytes
    return 1
  end

  -- log server could not be reached, must retry
  retry_delays[self.id] = (retry_delays[self.id] or 1) + 1
  local next_retry_delay = min(RETRY_MAX_DELAY, pow(retry_delays[self.id], 2))

  self.log(WARN, "could not reach log server, retrying in: ", next_retry_delay)

  to_send.retries = to_send.retries + 1
  -- add our data back to the sending queue, but at the end of it.
  if to_send.retries < self.retry_count then
    self.sending_queue[#self.sending_queue+1] = to_send
  else
    self.log(WARN, fmt("data was already tried %d times, dropping it",
                       to_send.retries))
  end

  return next_retry_delay
end


-------------------------------------------------------------------------------
-- Timer callback for issuing the `send` operation of the Sender.
-- @param premature boolean: ngx.timer premature indicator
-- @param self Buffer
-- @param to_send table: package to be sent, including `bytes` count,
-- `payload` data and `retries` counter.
-- @return nothing
run_sender = function(premature, self, to_send)
  if premature then
    return
  end

  local was_sent = self.sender:send(to_send.payload)

  local next_retry_delay = adjust_retries(self, to_send, was_sent)

  if #self.sending_queue > 0 then -- more to send?
    -- pop the oldest from the sending_queue
    self.log(DEBUG, fmt("sending oldest data, %d still queued",
                        #self.sending_queue-1))
    schedule_run_sender(self, remove(self.sending_queue, 1), next_retry_delay)
    return
  end

  -- we finished flushing the sending_queue, allow the creation
  -- of a future timer once the current data reached its limit
  -- and we trigger a flush()
  self.timer_send_pending = false
end


---------
-- Buffer
---------


-------------------------------------------------------------------------------
-- Initialize a generic log buffer.
-- @param id string: identifier for a per-worker retry policy.
-- @param conf table: plugin configuration table, optinally including
-- `retry_count`, `flush_timeout`, `queue_size` and `send_delay`.
-- @param producer table: a Producer object (see above).
-- @param sender table: a Sender object (see above).
-- @param log function: a logging function.
-- @return table: a Buffer object.
function Buffer.new(id, conf, producer, sender, log)
  assert(type(id) == "string",
         "arg #1 (id) must be a string")
  assert(type(conf) == "table",
         "arg #2 (conf) must be a table")
  assert(conf.retry_count == nil or type(conf.retry_count) == "number",
         "retry_count must be a number")
  assert(conf.flush_timeout == nil or type(conf.flush_timeout) == "number",
         "flush_timeout must be a number")
  assert(conf.queue_size == nil or type(conf.queue_size) == "number",
         "queue_size must be a number")
  assert(conf.send_delay == nil or type(conf.queue_size) == "number",
         "send_delay must be a number")
  assert(type(producer) == "table",
         "arg #3 (producer) must be a table")
  assert(type(producer.add_entry) == "function",
         "arg #3 (producer) must include an add_entry function")
  assert(type(producer.produce) == "function",
         "arg #3 (producer) must include a produce function")
  assert(type(producer.reset) == "function",
         "arg #3 (producer) must include a reset function")
  assert(type(sender) == "table",
         "arg #4 (sender) must be a table")
  assert(type(sender.send) == "function",
         "arg #4 (sender) must include a send function")
  assert(type(log) == "function",
         "arg #5 (log) must be a function")

  local self = {
    id = id,

    -- flush timeout in milliseconds
    flush_timeout = conf.flush_timeout and conf.flush_timeout * 1000 or 2000,

    retry_count = conf.retry_count or 0,
    queue_size = conf.queue_size or 1000,
    send_delay = conf.send_delay or 1,

    sending_queue = {}, -- FILO queue
    sending_queue_size = 0,

    timer_flush_pending = false,
    timer_send_pending = false,

    producer = producer,
    sender = sender,
    log = log,

    last_t = huge,
  }

  return setmetatable(self, Buffer_mt)
end


-------------------------------------------------------------------------------
-- Add data to be logged.
-- @param ... arguments that can be consumed by the Producer's
-- `add_entry` method.
-- @return true, or nil and an error message.
function Buffer:add_entry(...)
  local ok, size_or_err = self.producer:add_entry(...)
  if not ok then
    self.log(ERR, "could not add entry: ", size_or_err)
    return ok, size_or_err
  end

  if size_or_err >= self.queue_size then -- err is the queue size in this case
    local err
    ok, err = self:flush()
    if not ok then
      -- for our tests only
      return nil, err
    end
  elseif not self.timer_flush_pending then -- start delayed timer if none
    schedule_delayed_flush(self)
  end

  self.last_t = get_now()

  return true
end


-------------------------------------------------------------------------------
-- Flush data from the producer into the Buffer's internal
-- sending queue and trigger the Sender's `send` operation.
-- @return true, or nil and an error message.
function Buffer:flush()
  local produced, count_or_err, bytes = self.producer:produce()

  self.producer:reset()

  if not produced then
    self.log(ERR, "could not produce entries: ", count_or_err)
    return nil, count_or_err
  end

  if self.sending_queue_size + bytes > BUFFER_MAX_SIZE_BYTES then
    self.log(WARN, "buffer is full, discarding ", count_or_err, " entries")
    return nil, "buffer full"
  end

  self.log(DEBUG, "flushing entries for sending (", count_or_err, " entries)")

  if count_or_err > 0 then
    self.sending_queue_size = self.sending_queue_size + bytes
    self.sending_queue[#self.sending_queue + 1] = {
      payload = produced,
      bytes = bytes,
      retries = 0
    }
  end

  -- let's try to send. we might be sending older entries with
  -- this call, but that is fine, because as long as the sending_queue
  -- has elements, 'send()' will keep trying to flush it.
  self:send()

  return true
end


-------------------------------------------------------------------------------
-- Flush data from the producer into the Buffer's internal
-- sending queue and trigger the Sender's `send` operation.
-- @return true, or nil and an error message.
function Buffer:send()
  if #self.sending_queue < 1 then
    return nil, "empty queue"
  end

  -- only allow a single pending timer to send entries at a time
  -- this timer will keep calling itself while it has payloads
  -- to send.
  if not self.timer_send_pending then
    -- pop the oldest entry from the queue
    self.log(DEBUG, fmt("sending oldest entry, %d still queued",
                        #self.sending_queue-1))
    schedule_run_sender(self, remove(self.sending_queue, 1), self.send_delay)
  end

  return true
end


return Buffer
