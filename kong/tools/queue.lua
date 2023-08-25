-- Queue with retryable processing
--
-- This is a queue of "entries". Entries can be any Lua value.  A handler
-- function is called asynchronously to consume the entries and process them
-- (i.e. send them to an upstream server).
--
-- The maximum size of each batch of entries that is passed to the `handler`
-- function can be configured using the `max_batch_size` parameter.
--
-- The handler function can either return true if the entries
-- were successfully processed, or false and an error message to indicate that
-- processing has failed.  If processing has failed, the queue library will
-- automatically retry.
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
--   local handler_conf = {...}      -- configuration for queue handler
--   local queue_conf =              -- configuration for the queue itself (defaults shown unless noted)
--     {
--       name = "example",           -- name of the queue (required)
--       log_tag = "identifyme",     -- tag string to identify plugin or application area in logs
--       max_batch_size = 10,        -- maximum number of entries in one batch (default 1)
--       max_coalescing_delay = 1,   -- maximum number of seconds after first entry before a batch is sent
--       max_entries = 10,           -- maximum number of entries on the queue (default 10000)
--       max_bytes = 100,            -- maximum number of bytes on the queue (default nil)
--       initial_retry_delay = 0.01, -- initial delay when retrying a failed batch, doubled for each subsequent retry
--       max_retry_time = 60,        -- maximum number of seconds before a failed batch is dropped
--       max_retry_delay = 60,       -- maximum delay between send attempts, caps exponential retry
--     }
--
--   Queue.enqueue(queue_conf, handler, handler_conf, "Some value")
--   Queue.enqueue(queue_conf, handler, handler_conf, "Another value")
--
-- Given the example above,
--
-- * If the two `enqueue()` invocations are done within `max_coalescing_delay` seconds, they will be passed to the
--   handler function together in one batch.  The maximum number of entries in one batch is defined
--   by the `max_batch_size` parameter.
-- * The `max_entries` parameter defines how many entries can be waiting on the queue for transmission.  If
--   it is exceeded, the oldest entries on the queue will be discarded when new entries are queued.  Error
--   messages describing how many entries were lost will be logged.
-- * The `max_bytes` parameter, if set, indicates that no more than that number of bytes can be
--   waiting on a queue for transmission.  If it is set, only string entries must be queued and an error
--   message will be logged if an attempt is made to queue a non-string entry.
-- * When the `handler` function does not return a true value for a batch, it is retried for up to
--   `max_retry_time` seconds before the batch is deleted and an error is logged.  Retries are organized
--   by the queue library with the initial delay before retrying being defined by `initial_retry_delay` and
--   the maximum time between retries defined by `max_retry_delay` seconds.  For each subsequent retry, the
--   previous delay is doubled to yield an exponential back-off strategy - The first retry will be made quickly,
--   and each subsequent retry will be delayed longer.

local workspaces = require("kong.workspaces")
local semaphore = require("ngx.semaphore")
local table_new = require("table.new")


-- Minimum interval to warn about usage of legacy queueing related parameters
local MIN_WARNING_INTERVAL_SECONDS = 60



local assert = assert
local select = select
local pairs = pairs
local type = type
local setmetatable = setmetatable
local semaphore_new = semaphore.new
local math_min = math.min
local now = ngx.now
local sleep = ngx.sleep
local worker_exiting = ngx.worker.exiting
local null = ngx.null


local Queue = {}


-- Threshold to warn that the queue max_entries limit is reached
local CAPACITY_WARNING_THRESHOLD = 0.8
-- Time in seconds to poll for worker shutdown when coalescing entries
local COALESCE_POLL_TIME = 1.0
-- If remaining coalescing wait budget is less than this number of seconds,
-- then just send the batch without waiting any further
local COALESCE_MIN_TIME = 0.05


local Queue_mt = {
  __index = Queue
}


local function make_queue_key(name)
  return (workspaces.get_workspace_id() or "") .. "." .. name
end


local queues = {}


function Queue.exists(name)
  return queues[make_queue_key(name)] and true or false
end

-------------------------------------------------------------------------------
-- Initialize a queue with background retryable processing
-- @param process function, invoked to process every payload generated
-- @param opts table, requires `name`, optionally includes `retry_count`, `max_coalescing_delay` and `max_batch_size`
-- @return table: a Queue object.
local function get_or_create_queue(queue_conf, handler, handler_conf)

  local name = assert(queue_conf.name)
  local key = make_queue_key(name)

  local queue = queues[key]
  if queue then
    queue:log_debug("queue exists")
    -- We always use the latest configuration that we have seen for a queue and handler.
    queue.handler_conf = handler_conf
    return queue
  end

  queue = {
    -- Queue parameters from the enqueue call
    name = name,
    key = key,
    handler = handler,
    handler_conf = handler_conf,

    -- semaphore to count the number of items on the queue and synchronize between enqueue and handler
    semaphore = semaphore_new(),

    -- `bytes_queued` holds the number of bytes on the queue.  It will be used only if max_bytes is set.
    bytes_queued = 0,
    -- `entries` holds the actual queue items.
    entries = table_new(32, 0),
    -- Pointers into the table that holds the actual queued entries.  `front` points to the oldest, `back` points to
    -- the newest entry.
    front = 1,
    back = 1,
  }
  for option, value in pairs(queue_conf) do
    queue[option] = value
  end

  queue = setmetatable(queue, Queue_mt)

  kong.timer:named_at("queue " .. key, 0, function(_, q)
    while q:count() > 0 do
      q:log_debug("processing queue")
      q:process_once()
    end
    q:log_debug("done processing queue")
    queues[key] = nil
  end, queue)

  queues[key] = queue

  queue:log_debug("queue created")

  return queue
end


-------------------------------------------------------------------------------
-- Log a message that includes the name of the queue for identification purposes
-- @param self Queue
-- @param level: log level
-- @param formatstring: format string, will get the queue name and ": " prepended
-- @param ...: formatter arguments
function Queue:log(handler, formatstring, ...)
  local message = "[" .. (self.log_tag or "") .. "] queue " .. self.name .. ": " .. formatstring
  if select('#', ...) > 0 then
    return handler(string.format(message, unpack({...})))
  else
    return handler(message)
  end
end

function Queue:log_debug(...) self:log(kong.log.debug, ...) end
function Queue:log_info(...) self:log(kong.log.info, ...) end
function Queue:log_warn(...) self:log(kong.log.warn, ...) end
function Queue:log_err(...) self:log(kong.log.err, ...) end


function Queue:count()
  return self.back - self.front
end


-- Delete the frontmost entry from the queue and adjust the current utilization variables.
function Queue:delete_frontmost_entry()
  if self.max_bytes then
    -- If max_bytes is set, reduce the currently queued byte count by the
    self.bytes_queued = self.bytes_queued - #self.entries[self.front]
  end
  self.entries[self.front] = nil
  self.front = self.front + 1
  if self.front == self.back then
    self.front = 1
    self.back = 1
  end
end


-- Drop the oldest entry, adjusting the semaphore value in the process.  This is
-- called when the queue runs out of space and needs to make space.
function Queue:drop_oldest_entry()
  assert(self.semaphore:count() > 0)
  self.semaphore:wait(0)
  self:delete_frontmost_entry()
end


-- Process one batch of entries from the queue.  Returns truthy if entries were processed, falsy if there was an
-- error or no items were on the queue to be processed.
function Queue:process_once()
  local ok, err = self.semaphore:wait(0)
  if not ok then
    if err ~= "timeout" then
      -- We can't do anything meaningful to recover here, so we just log the error.
      self:log_err('error waiting for semaphore: %s', err)
    end
    return
  end
  local data_started = now()

  local entry_count = 1

  -- We've got our first entry from the queue.  Collect more entries until max_coalescing_delay expires or we've collected
  -- max_batch_size entries to send
  while entry_count < self.max_batch_size
    and self.max_coalescing_delay - (now() - data_started) >= COALESCE_MIN_TIME and not worker_exiting()
  do
    -- Instead of waiting for the coalesce time to expire, we cap the semaphore wait to COALESCE_POLL_TIME
    -- so that we can check for worker shutdown periodically.
    local wait_time = math_min(self.max_coalescing_delay - (now() - data_started), COALESCE_POLL_TIME)

    if ngx.worker.exiting() then
      -- minimize coalescing delay during shutdown to quickly process remaining entries
      self.max_coalescing_delay = COALESCE_MIN_TIME
      wait_time = COALESCE_MIN_TIME
    end

    ok, err = self.semaphore:wait(wait_time)
    if not ok and err ~= "timeout" then
      self:log_err("could not wait for semaphore: %s", err)
      break
    elseif ok then
      entry_count = entry_count + 1
    end
  end

  local start_time = now()
  local retry_count = 0
  while true do
    self:log_debug("passing %d entries to handler", entry_count)
    ok, err = self.handler(self.handler_conf, {unpack(self.entries, self.front, self.front + entry_count - 1)})
    if ok then
      self:log_debug("handler processed %d entries sucessfully", entry_count)
      break
    end

    if not err then
      self:log_err("handler returned falsy value but no error information")
    end

    if (now() - start_time) > self.max_retry_time then
      self:log_err(
        "could not send entries, giving up after %d retries.  %d queue entries were lost",
        retry_count, entry_count)
      break
    end

    self:log_warn("handler could not process entries: %s", tostring(err))

    -- Delay before retrying.  The delay time is calculated by multiplying the configured initial_retry_delay with
    -- 2 to the power of the number of retries, creating an exponential increase over the course of each retry.
    -- The maximum time between retries is capped by the max_retry_delay configuration parameter.
    sleep(math_min(self.max_retry_delay, 2 ^ retry_count * self.initial_retry_delay))
    retry_count = retry_count + 1
  end

  -- Guard against queue shrinkage during handler invocation by using math.min below.
  for _ = 1, math.min(entry_count, self:count()) do
    self:delete_frontmost_entry()
  end
  if self.queue_full then
    self:log_info('queue resumed processing')
    self.queue_full = false
  end
end


local legacy_params_warned = {}

local function maybe_warn(name, message)
  local key = name .. "/" .. message
  if ngx.now() - (legacy_params_warned[key] or 0) >= MIN_WARNING_INTERVAL_SECONDS then
    kong.log.warn(message)
    legacy_params_warned[key] = ngx.now()
  end
end


-- This function retrieves the queue parameters from a plugin configuration, converting legacy parameters
-- to their new locations.
function Queue.get_plugin_params(plugin_name, config, queue_name)
  local queue_config = config.queue or table_new(0, 5)

  -- create a tag to put into log files that identifies the plugin instance
  local log_tag = plugin_name .. " plugin " .. kong.plugin.get_id()
  if config.plugin_instance_name then
    log_tag = log_tag .. " (" .. config.plugin_instance_name .. ")"
  end
  queue_config.log_tag = log_tag

  if not queue_config.name then
    queue_config.name = queue_name or kong.plugin.get_id()
  end

  -- It is planned to remove the legacy parameters in Kong Gateway 4.0, removing
  -- the need for the checks below. ({ after = "4.0", })
  if (config.retry_count or null) ~= null and config.retry_count ~= 10 then
    maybe_warn(
      queue_config.name,
      "the retry_count parameter no longer works, please update "
        .. "your configuration to use initial_retry_delay and max_retry_time instead")
  end

  if (config.queue_size or null) ~= null and config.queue_size ~= 1 then
    queue_config.max_batch_size = config.queue_size
    maybe_warn(
      queue_config.name,
      "the queue_size parameter is deprecated, please update your "
        .. "configuration to use queue.max_batch_size instead")
  end

  if (config.flush_timeout or null) ~= null and config.flush_timeout ~= 2 then
    queue_config.max_coalescing_delay = config.flush_timeout
    maybe_warn(
      queue_config.name,
      "the flush_timeout parameter is deprecated, please update your "
        .. "configuration to use queue.max_coalescing_delay instead")
  end

  if (config.batch_span_count or null) ~= null and config.batch_span_count ~= 200 then
    queue_config.max_batch_size = config.batch_span_count
    maybe_warn(
      queue_config.name,
      "the batch_span_count parameter is deprecated, please update your "
        .. "configuration to use queue.max_batch_size instead")
  end

  if (config.batch_flush_delay or null) ~= null and config.batch_flush_delay ~= 3 then
    queue_config.max_coalescing_delay = config.batch_flush_delay
    maybe_warn(
      queue_config.name,
      "the batch_flush_delay parameter is deprecated, please update your "
        .. "configuration to use queue.max_coalescing_delay instead")
  end
  return queue_config
end


-------------------------------------------------------------------------------
-- Add entry to the queue
-- @param conf plugin configuration of the plugin instance that caused the item to be queued
-- @param entry the value included in the queue. It can be any Lua value besides nil.
-- @return true, or nil and an error message.
local function enqueue(self, entry)
  if entry == nil then
    return nil, "entry must be a non-nil Lua value"
  end

  if self:count() >= self.max_entries * CAPACITY_WARNING_THRESHOLD then
    if not self.warned then
      self:log_warn('queue at %s%% capacity', CAPACITY_WARNING_THRESHOLD * 100)
      self.warned = true
    end
  else
    self.warned = nil
  end

  if self:count() == self.max_entries then
    if not self.queue_full then
      self.queue_full = true
      self:log_err("queue full, dropping old entries until processing is successful again")
    end
    self:drop_oldest_entry()
  end

  if self.max_bytes then
    if type(entry) ~= "string" then
      self:log_err("queuing non-string entry to a queue that has queue.max_bytes set, capacity monitoring will not be correct")
    else
      if #entry > self.max_bytes then
        local message = string.format(
          "string to be queued is longer (%d bytes) than the queue's max_bytes (%d bytes)",
          #entry, self.max_bytes)
        self:log_err(message)
        return nil, message
      end

      local dropped = 0
      while self:count() > 0 and (self.bytes_queued + #entry) > self.max_bytes do
        self:drop_oldest_entry()
        dropped = dropped + 1
      end
      if dropped > 0 then
        self.queue_full = true
        self:log_err("byte capacity exceeded, %d queue entries were dropped", dropped)
      end

      self.bytes_queued = self.bytes_queued + #entry
    end
  end

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

  local queue = get_or_create_queue(queue_conf, handler, handler_conf)
  return enqueue(queue, value)
end

-- For testing, the _exists() function is provided to allow a test to wait for the
-- queue to have been completely processed.
function Queue._exists(name)
  local queue = queues[make_queue_key(name)]
  return queue and queue:count() > 0
end


Queue._CAPACITY_WARNING_THRESHOLD = CAPACITY_WARNING_THRESHOLD


return Queue
