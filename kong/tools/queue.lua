-- Queue with retryable processing
--
-- This is a queue of "entries". Entries can be any Lua value.
--
-- The queue has two mandatory parameters:
--
-- `name` is the name of the queue. It uniquely identifies the queue across the
-- system.  If two plugin instances use the same queue name, they will share one
-- queue and their queue related configuration must match.
--
-- `handler` is the function which consumes entries.
--
-- Entries are dequeued in batches.  The maximum size of each batch of entries
-- that is passed to the `handler` function can be configured using the
-- `batch_max_size` parameter.
--
-- The handler function can either return true if the entries
-- were successfully processed, or false and an error message to indicate that
-- processing has failed.  If processing has failed, the queue library will
-- automatically retry.
--
-- If the `batch_max_size` parameter is larger than 1, processing of the
-- queue will only start after `max_delay` milliseconds have elapsed if
-- less than `batch_max_size` entries are waiting on the queue.  If `batch_max_size`
-- is 1, the queue will be processed immediately.
--
-- Usage:
--
--   local Queue = require "kong.tools.queue"
--
--   local handler = function(conf, entries)
--     -- must return true if ok, or false + error otherwise
--     return true
--   end
--
--   local handler_conf = {...}  -- configuration for queue handler
--   local queue_conf =          -- configuration for the queue itself (defaults shown unless noted)
--     {
--       name = "example",       -- name of the queue (required)
--       batch_max_size = 10,    -- maximum number of entries in one batch (default 1)
--       max_delay = 1,          -- maximum number of seconds after first entry before a batch is sent
--       capacity = 10,          -- maximum number of entries on the queue (default 10000)
--       string_capacity = 100,  -- maximum number of bytes on the queue (default nil)
--       max_retry_time = 60,    -- maximum number of seconds before a failed batch is dropped
--       max_retry_delay = 60,   -- maximum delay between send attempts
--     }
--
--   Queue.enqueue(queue_conf, handler, handler_conf, "Some value")
--   Queue.enqueue(queue_conf, handler, handler_conf, "Another value")
--
-- Given the example above,
--
-- * If the two `enqueue()` invocations are done within `max_delay` seconds, they will be passed to the
--   handler function together in one batch.  The maximum number of entries in one batch is defined
--   by the `batch_max_size` parameter.
-- * The `capacity` parameter defines how many entries can be waiting on the queue for transmission.  If
--   it is exceeded, the oldest entries on the queue will be discarded when new entries are queued.  Error
--   messages describing how many entries were lost will be logged.
-- * The `string_capacity` parameter, if set, indicates that no more than that number of bytes can be
--   waiting on a queue for transmission.  If it is set, only string entries must be queued and an error
--   message will be logged if an attempt is made to queue a non-string entry.
-- * When the `handler` function does not return a true value for a batch, it is retried for up to
--   `max_retry_time` seconds before the batch is deleted and an error is logged.  Retries are organized
--   by the queue library using an exponential back-off algorithm with the maximum time between retries
--   set to `max_retry_delay` seconds.

local semaphore = require "ngx.semaphore"

local DEBUG = ngx.DEBUG
local INFO = ngx.INFO
local WARN = ngx.WARN
local ERR = ngx.ERR


local function now()
  ngx.update_time()
  return ngx.now()
end


local Queue = {
  POLL_TIME = 1,
  MAX_IDLE_TIME = 60,
}

local Queue_mt = {
  __index = Queue
}


local queues = {}


function Queue.exists(name)
  return queues[name] and true or false
end

-------------------------------------------------------------------------------
-- Initialize a queue with background retryable processing
-- @param process function, invoked to process every payload generated
-- @param opts table, requires `name`, optionally includes `retry_count`, `max_delay` and `batch_max_size`
-- @return table: a Queue object.
local function get_queue(queue_conf, handler, handler_conf)

  assert(type(queue_conf.name) == "string",
    "missing name in queue configuration")

  local name = queue_conf.name

  local queue = queues[name]
  if queue then
    queue:log(DEBUG, "queue exists")
    queue.handler_conf = handler_conf
    return queue
  end

  queue = {
    name = name,
    handler = handler,
    handler_conf = handler_conf,

    semaphore = semaphore.new(),
    retry_delay = 1,

    last_used = now(),
    bytes_queued = 0,
    front = 1,
    back = 1,
    entries = {},
  }
  for option, value in pairs(queue_conf) do
    queue[option] = value
  end

  queue = setmetatable(queue, Queue_mt)

  kong.timer:named_every(name, Queue.POLL_TIME, function(premature, q)

    -- This is the "background task" that consumes queue entries.
    if premature then
      -- Kong is exiting gracefully and has invoked our timer handler one last time - Drain the queue
      q:log(DEBUG, "shutting down queue")
      q:_drain()
      return
    end

    if (q:count() == 0) and ((now() - q.last_used) >= Queue.MAX_IDLE_TIME) then
      -- Queue has not been used longer than Queue.MAX_IDLE_TIME
      kong.timer:cancel(name)
      queues[name] = nil
      return
    end

    while q:count() do
      q:log(DEBUG, "processing queue")
      if not q:process_once(0) then
        q:log(DEBUG, "stop this timer run because sending a batch failed")
        break
      end
    end
  end, queue)

  queues[name] = queue

  queue:log(DEBUG, "queue created")

  return queue
end


-------------------------------------------------------------------------------
-- Log a message that includes the name of the queue for identification purposes
-- @param self Queue
-- @param level: log level
-- @param formatstring: format string, will get the queue name and ": " prepended
-- @param ...: formatter arguments
function Queue:log(level, formatstring, ...)
  local message = self.name .. ": " .. formatstring
  if select('#', ...) > 0 then
    return ngx.log(level, string.format(message, unpack({...})))
  else
    return ngx.log(level, message)
  end
end


function Queue:count()
  return self.back - self.front
end


function Queue:delete_frontmost_entry()
  if self.string_capacity then
    self.bytes_queued = self.bytes_queued - #self.entries[self.front]
  end
  self.entries[self.front] = nil
  self.front = self.front + 1
  if self.front == self.back then
    self.front = 1
    self.back = 1
  end
end


function Queue:process_once(timeout)
  local ok, err = self.semaphore:wait(timeout)
  if not ok then
    if err ~= "timeout" then
      self:log(ERR, 'error waiting for semaphore: %s', err)
    end
    return
  end
  self.last_used = now()
  local data_started = now()

  local entry_count = 1

  -- We've got our first entry from the queue.  Collect more entries until max_delay expires or we've collected
  -- batch_max_size entries to send
  while entry_count < self.batch_max_size and (now() - data_started) < self.max_delay and not ngx.worker.exiting() do
    self.last_used = now()
    ok, err = self.semaphore:wait(((data_started + self.max_delay) - now()) / 1000)
    if not ok and err == "timeout" then
      break
    elseif ok then
      entry_count = entry_count + 1
    else
      self:log(ERR, "could not wait for semaphore: %s", err)
      break
    end
  end

  local start_time = now()
  local retry_count = 0
  local success
  while true do
    self:log(DEBUG, "passing %d entries to handler", entry_count)
    self.last_used = now()
    ok, err = self.handler(self.handler_conf, {unpack(self.entries, self.front, self.front + entry_count - 1)})
    if ok then
      self:log(DEBUG, "handler processed %d entries sucessfully", entry_count)
      success = true
      break
    end

    if not err then
      self:log(ERR, "handler returned falsy value but no error information")
    end

    if (now() - start_time) > self.max_retry_time then
      self:log(
        ERR,
        "could not send entries, giving up after %d retries.  %d queue entries were lost",
        retry_count, entry_count)
      break
    end

    self:log(WARN, "handler could not process entries: %s", tostring(err))
    retry_count = retry_count + 1
    self.last_used = now()
    ngx.sleep(math.min(self.max_retry_delay, (retry_count * retry_count) * 0.01))
  end

  -- Guard against queue shrinkage during handler invocation by using match.min below.
  for _ = 1, math.min(entry_count, self:count()) do
    self:delete_frontmost_entry()
  end
  if self.queue_full then
    self:log(INFO, 'queue resumed processing')
    self.queue_full = false
  end

  return success
end


function Queue.get_params(config)
  local queue_config = unpack({ config.queue or {}})
  if config.retry_count and config.retry_count ~= ngx.null then
    ngx.log(ngx.WARN, string.format(
      "deprecated `retry_count` parameter in plugin %s ignored",
      kong.plugin.get_id()))
  end
  if config.queue_size and config.queue_size ~= ngx.null then
    ngx.log(ngx.WARN, string.format(
      "deprecated `queue_size` parameter in plugin %s converted to `queue.batch_max_size`",
      kong.plugin.get_id()))
    queue_config.batch_max_size = config.queue_size
  end
  if config.flush_timeout  and config.flush_timeout ~= ngx.null then
    ngx.log(ngx.WARN, string.format(
      "deprecated `flush_timeout` parameter in plugin %s converted to `queue.max_delay`",
      kong.plugin.get_id()))
    queue_config.max_delay = config.flush_timeout
  end
  if not queue_config.name then
    queue_config.name = kong.plugin.get_id()
  end
  return queue_config
end


-------------------------------------------------------------------------------
-- Drain the queue, used during orderly shutdown and for testing.
-- @param self Queue
function Queue:_drain()
  while self:count() > 0 do
    self:process_once(0.01)
  end
end


-------------------------------------------------------------------------------
-- Add entry to the queue
-- @param conf plugin configuration of the plugin instance that caused the item to be queued
-- @param entry the value included in the queue. It can be any Lua value besides nil.
-- @return true, or nil and an error message.
function Queue:_enqueue(entry)
  if entry == nil then
    return nil, "entry must be a non-nil Lua value"
  end

  if self:count() >= self.capacity * 0.9 then
    if not self.warned then
      self:log(WARN, 'queue at 90% capacity')
      self.warned = true
    end
  else
    self.warned = nil
  end

  if self:count() == self.capacity then
    if not self.queue_full then
      self.queue_full = true
      self:log(ERR, "queue full, dropping old entries until processing is successful again")
    end
    self:delete_frontmost_entry()
  end

  if self.string_capacity then
    if type(entry) ~= "string" then
      self:log(ERR, "queuing non-string entry to a queue that has queue.string_capacity set, capacity monitoring will not be correct")
    else
      if #entry > self.string_capacity then
        self:log(ERR,
          "string to be queued is longer (%d bytes) than the queue's string_capacity (%d bytes)",
          #entry, self.string_capacity)
        return
      end

      local dropped = 0
      while self:count() > 0 and (self.bytes_queued + #entry) > self.string_capacity do
        self:delete_frontmost_entry()
        dropped = dropped + 1
      end
      if dropped > 0 then
        self:log(ERR, "string capacity exceeded, %d queue entries were dropped", dropped)
      end

      self.bytes_queued = self.bytes_queued + #entry
    end
  end

  self.last_used = now()
  self.entries[self.back] = entry
  self.back = self.back + 1
  self.semaphore:post()

  return true
end


function Queue.enqueue(queue_conf, handler, handler_conf, value)

  assert(type(queue_conf) == "table",
    "arg #1 (queue_conf) must be a table")
  assert(type(handler) == "function",
    "arg #2 (handler) must be a function")
  assert(handler_conf == nil or type(handler_conf) == "table",
    "arg #3 (handler_conf) must be a table")

  assert(type(queue_conf.name) == "string",
    "arg #1 (queue_conf) must include a name")

  return get_queue(queue_conf, handler, handler_conf):_enqueue(value)
end

-- for testing:
function Queue.drain(name)
  local queue = assert(queues[name])
  queue:_drain()
end


return Queue
