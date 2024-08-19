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


local function _make_queue_key(name)
  return (workspaces.get_workspace_id() or "") .. "." .. name
end


local function _remaining_capacity(self)
  local remaining_entries = self.max_entries - self:count()
  local max_bytes = self.max_bytes

  -- we enqueue entries one by one,
  -- so it is impossible to have a negative value
  assert(remaining_entries >= 0, "queue should not be over capacity")

  if not max_bytes then
    return remaining_entries
  end

  local remaining_bytes = max_bytes - self.bytes_queued

  -- we check remaining_bytes before enqueueing an entry,
  -- so it is impossible to have a negative value
  assert(remaining_bytes >= 0, "queue should not be over capacity")

  return remaining_entries, remaining_bytes
end


local function _is_reaching_max_entries(self)
  -- `()` is used to get the first return value only
  return (_remaining_capacity(self)) == 0
end


local function _will_exceed_max_entries(self)
   -- `()` is used to get the first return value only
  return (_remaining_capacity(self)) - 1 < 0
end


local function _is_entry_too_large(self, entry)
  local max_bytes = self.max_bytes

  if not max_bytes then
    return false
  end

  if type(entry) ~= "string" then
    -- handle non-string entry, including `nil`
    return false
  end

  return #entry > max_bytes
end


local function _is_reaching_max_bytes(self)
  if not self.max_bytes then
    return false
  end

  local _, remaining_bytes = _remaining_capacity(self)
  return remaining_bytes == 0
end


local function _will_exceed_max_bytes(self, entry)
  if not self.max_bytes then
    return false
  end

  if type(entry) ~= "string" then
    -- handle non-string entry, including `nil`
    return false
  end

  local _, remaining_bytes = _remaining_capacity(self)
  return #entry > remaining_bytes
end


local function _is_full(self)
  return _is_reaching_max_entries(self) or _is_reaching_max_bytes(self)
end


local function _can_enqueue(self, entry)
  return not (
    _is_full(self)                       or
    _is_entry_too_large(self, entry)     or
    _will_exceed_max_entries(self)       or
    _will_exceed_max_bytes(self, entry)
  )
end


local queues = {}


function Queue.exists(name)
  return queues[_make_queue_key(name)] and true or false
end

-------------------------------------------------------------------------------
-- Initialize a queue with background retryable processing
-- @param process function, invoked to process every payload generated
-- @param opts table, requires `name`, optionally includes `retry_count`, `max_coalescing_delay` and `max_batch_size`
-- @return table: a Queue object.
local function get_or_create_queue(queue_conf, handler, handler_conf)

  local name = assert(queue_conf.name)
  local key = _make_queue_key(name)

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

  if queue.concurrency_limit == 1 then
    kong.timer:named_at("queue " .. key, 0, function(_, q)
      while q:count() > 0 do
        q:log_debug("processing queue")
        q:process_once()
      end
      q:log_debug("done processing queue")
      queues[key] = nil
    end, queue)
    queues[key] = queue
  end


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


function Queue.is_full(queue_conf)
  local queue = queues[_make_queue_key(queue_conf.name)]
  if not queue then
    -- treat non-existing queues as not full as they will be created on demand
    return false
  end

  return _is_full(queue)
end


function Queue.can_enqueue(queue_conf, entry)
  local queue = queues[_make_queue_key(queue_conf.name)]
  if not queue then
    -- treat non-existing queues having enough capacity.
    -- WARNING: The limitation is that if the `entry` is a string and the `queue.max_bytes` is set,
    --          and also the `#entry` is larger than `queue.max_bytes`,
    --          this function will incorrectly return `true` instead of `false`.
    --          This is a limitation of the current implementation.
    --          All capacity checking functions need a Queue instance to work correctly.
    --          constructing a Queue instance just for this function is not efficient,
    --          so we just return `true` here.
    --          This limitation should not happen in normal usage,
    --          as user should be aware of the queue capacity settings
    --          to avoid such situation.
    return true
  end

  return _can_enqueue(queue, entry)
end

local function handle(self, entries)
  local entry_count = #entries

  local start_time = now()
  local retry_count = 0
  while true do
    self:log_debug("passing %d entries to handler", entry_count)
    local status, ok, err = pcall(self.handler, self.handler_conf, entries)
    if status and ok == true then
      self:log_debug("handler processed %d entries successfully", entry_count)
      break
    end

    if not status then
      -- protected call failed, ok is the error message
      err = ok
    end

    self:log_warn("handler could not process entries: %s", tostring(err or "no error details returned by handler"))

    if not err then
      self:log_err("handler returned falsy value but no error information")
    end

    if (now() - start_time) > self.max_retry_time then
      self:log_err(
        "could not send entries due to max_retry_time exceeded. %d queue entries were lost",
        entry_count)
      break
    end

    -- Delay before retrying.  The delay time is calculated by multiplying the configured initial_retry_delay with
    -- 2 to the power of the number of retries, creating an exponential increase over the course of each retry.
    -- The maximum time between retries is capped by the max_retry_delay configuration parameter.
    sleep(math_min(self.max_retry_delay, 2 ^ retry_count * self.initial_retry_delay))
    retry_count = retry_count + 1
  end
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
    and self.max_coalescing_delay - (now() - data_started) >= COALESCE_MIN_TIME
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

  local batch = {unpack(self.entries, self.front, self.front + entry_count - 1)}
  for _ = 1, entry_count do
    self:delete_frontmost_entry()
  end
  if self.already_dropped_entries then
    self:log_info('queue resumed processing')
    self.already_dropped_entries = false
  end

  handle(self, batch)
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

  if self.concurrency_limit == -1 then -- unlimited concurrency
    -- do not enqueue when concurrency_limit is unlimited
    local ok, err = kong.timer:at(0, function(premature)
      if premature then
        return
      end
      handle(self, { entry })
    end)
    if not ok then
      return nil, "failed to crete timer: " .. err
    end
    return true
  end


  if self:count() >= self.max_entries * CAPACITY_WARNING_THRESHOLD then
    if not self.warned then
      self:log_warn('queue at %s%% capacity', CAPACITY_WARNING_THRESHOLD * 100)
      self.warned = true
    end
  else
    self.warned = nil
  end

  if _is_reaching_max_entries(self) then
    self:log_err("queue full, dropping old entries until processing is successful again")
    self:drop_oldest_entry()
    self.already_dropped_entries = true
  end

  if _is_entry_too_large(self, entry) then
    local err_msg = string.format(
      "string to be queued is longer (%d bytes) than the queue's max_bytes (%d bytes)",
      #entry,
      self.max_bytes
    )
    self:log_err(err_msg)

    return nil, err_msg
  end

  if _will_exceed_max_bytes(self, entry) then
    local dropped = 0

    repeat
      self:drop_oldest_entry()
      dropped = dropped + 1
      self.already_dropped_entries = true
    until not _will_exceed_max_bytes(self, entry)

    self:log_err("byte capacity exceeded, %d queue entries were dropped", dropped)
  end

  -- safety guard
  -- The queue should not be full if we are running into this situation.
  -- Since the dropping logic is complicated,
  -- further maintenancers might introduce bugs,
  -- so I added this assertion to detect this kind of bug early.
  -- It's better to crash early than leak memory
  -- as analyze memory leak is hard.
  assert(
    -- assert that enough space is available on the queue now
    _can_enqueue(self, entry),
    "queue should not be full after dropping entries"
  )

  if self.max_bytes then
    if type(entry) ~= "string" then
      self:log_err("queuing non-string entry to a queue that has queue.max_bytes set, capacity monitoring will not be correct")
    end

    self.bytes_queued = self.bytes_queued + #entry
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
    "arg #3 (handler_conf) must be a table or nil")
  assert(type(queue_conf.name) == "string",
    "arg #1 (queue_conf) must include a name")

  assert(
    type(queue_conf.max_batch_size) == "number",
    "arg #1 (queue_conf) max_batch_size must be a number"
  )
  assert(
    type(queue_conf.max_coalescing_delay) == "number",
    "arg #1 (queue_conf) max_coalescing_delay must be a number"
  )
  assert(
    type(queue_conf.max_entries) == "number",
    "arg #1 (queue_conf) max_entries must be a number"
  )
  assert(
    type(queue_conf.max_retry_time) == "number",
    "arg #1 (queue_conf) max_retry_time must be a number"
  )
  assert(
    type(queue_conf.initial_retry_delay) == "number",
    "arg #1 (queue_conf) initial_retry_delay must be a number"
  )
  assert(
    type(queue_conf.max_retry_delay) == "number",
    "arg #1 (queue_conf) max_retry_delay must be a number"
  )

  local max_bytes_type = type(queue_conf.max_bytes)
  assert(
    max_bytes_type == "nil" or max_bytes_type == "number",
    "arg #1 (queue_conf) max_bytes must be a number or nil"
  )

  assert(
    type(queue_conf.concurrency_limit) == "number",
    "arg #1 (queue_conf) concurrency_limit must be a number"
  )

  local queue = get_or_create_queue(queue_conf, handler, handler_conf)
  return enqueue(queue, value)
end

-- For testing, the _exists() function is provided to allow a test to wait for the
-- queue to have been completely processed.
function Queue._exists(name)
  local queue = queues[_make_queue_key(name)]
  return queue and queue:count() > 0
end


-- [[ For testing purposes only
Queue._CAPACITY_WARNING_THRESHOLD = CAPACITY_WARNING_THRESHOLD
-- ]]


return Queue
