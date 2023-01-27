--[[
TODO:

queue objects cannot be held on to because they may be garbage collected.  safer API?
replace loop by ngx.every?
use timerng:named_at instead of ngx.timer.at
update documentation
metrics
when at capacity, remove currently sent *batch* from the front
use in/out pointer instead of array manipulation
]]



-- Queue with background retryable processing
--
-- This is a queue of "entries". Entries can be any Lua value.
--
-- The queue has two mandatory parameters:  `name` is the name of the queue,
-- used to identify it in log messages, and `handler`, which is the
-- function which consumes entries.  Entries are dequeued in batches.  The
-- maximum size of each batch of entries that is passed to the `handler`
-- function can be configured using the `batch_max_size` parameter.
--
-- The handler function can either return true if the entries
-- were successfully processed, or false and an error message to indicate that
-- processing has failed.  If processing has failed, the queue library will
-- automatically retry.
--
-- If the `batch_max_size` parameter is larger than 1, processing of the
-- queue will only start after `max_delay` milliseconds have elapsed while
-- than `batch_max_size` entries are waiting on the queue.  If `batch_max_size`
-- is 1, the queue will be processed immediately.
--
-- Usage:
--
--   local Queue = require "kong.tools.queue"
--
--   local handler = function(entries)
--     -- must return true if ok, or false + error otherwise
--     return true
--   end
--
--   local q = Queue.new(
--     "example",
--     handler, -- function used to process values from the queue
--     { -- Opts table with control values. Defaults shown:
--       retry_count      = 0,    -- number of times to retry processing
--       batch_max_size   = 1000, -- max number of entries that handed to the process function in one invocation
--       max_delay        = 1000, -- processing delay in milliseconds
--     }
--   )
--
--   q:add("Some value")
--   q:add("Some other value")
--
--   ...
--
-- Given the example above,
--
-- * If the two `q:add()` invocations are done in quick succession, they will be passed to the
--   handler function together in one batch.
-- * If processing fails, it will not be retried (retry_count equals 0)
-- * If retry_count was bigger than 0, processing would be re-queued n times before finally being discarded.
-- * The retries are not regular: every time the handler fails, they next retry is delayed by n_try^2, up to 60s.
--
-- The most important internal attributes of Queue are:
--
-- * `self.queue`: This is an array of entries, which are awaiting processing/consumption
--
-- Each entry has the following structure:
-- {
--   data = "some data",     -- data to process
--   config = {...},         -- plugin configuration that caused the entry to be created
--   timestamp = 12345789,   -- timestamp when the entry was queued
-- }


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
  configuration_fields = {
    name = {
      type = "string",
      description = "name of the queue",
    },
    batch_max_size = {
      type = "number",
      default = 1,
      description = "maximum number of entries to be given to the handler as a batch"
    },
    max_delay = {
      type = "number",
      default = 1,
      description = "maximum number of (fractional) seconds to elapse after the first entry was queued before the queue starts calling the handler",
    },
    capacity = {
      type = "number",
      default = 10000,
      description = "maximum number of entries that can be waiting on the queue",
    },
    string_capacity = {
      type = "number",
      default = nil,
      description = "maximum number of bytes that can be waiting on a queue, requires string content",
    },
    max_retry_time = {
      type = "number",
      default = 60,
      description = "time in seconds before the queue gives up calling a failed handler for a batch",
    },
    max_retry_delay = {
      type = "number",
      default = 60,
      description = "maximum time in seconds between retries, caps exponential backoff"
    },
    poll_time = {
      type = "number",
      default = 1,
      description = "time in seconds between polls for worker shutdown",
    },
    max_idle_time = {
      type = "number",
      default = 60,
      description = "time in seconds before an idle queue is deleted",
    },
  },
  configuration_schema = {}
}

for name, schema in pairs(Queue.configuration_fields) do
  -- can't use schema directly because Josh's `description` has not yet been implemented.
  table.insert(Queue.configuration_schema, { [name] = { type = schema.type, default = schema.default } })
end


local Queue_mt = {
  __index = Queue
}


---------
-- Queue
---------


local function make_queue_name(plugin_name, queue_name)
  return plugin_name .. "." .. queue_name
end

local queues = {}


function Queue.exists(plugin_name, queue_name)
  return queues[make_queue_name(plugin_name, queue_name)] and true or false
end

-------------------------------------------------------------------------------
-- Initialize a queue with background retryable processing
-- @param name string to identify the queue in log messages
-- @param process function, invoked to process every payload generated
-- @param opts table, optionally including `retry_count`, `max_delay` and `batch_max_size`
-- @return table: a Queue object.
function Queue.get(plugin_name, handler, opts)

  assert(type(plugin_name) == "string",
    "arg #1 (plugin_name) must be a string")
  assert(type(handler) == "function",
    "arg #2 (handler) must be a function")
  assert(type(opts) == "table",
    "arg #3 (opts) must be a table")
  assert(type(opts.name) == "string",
    "opts.name must be a string")

  local queue_name = make_queue_name(plugin_name, opts.name)
  local queue = queues[queue_name]
  if queue then
    queue:log(DEBUG, "queue exists")
    for name, _ in pairs(Queue.configuration_fields) do
      if queue[name] ~= opts[name] then
        queue:log(ERR, "inconsistent parameter %s for queue %s.%s", name, plugin_name, queue.name)
      end
    end
    return queue
  end

  queue = {
    plugin_name = plugin_name,
    handler = handler,

    semaphore = semaphore.new(),
    retry_delay = 1,

    running = true,
    last_used = now(),
    bytes_queued = 0,
    queue = {},
  }

  for name, _ in pairs(opts) do
    assert(Queue.configuration_fields[name], name .. " is not a valid queue parameter")
  end

  for name, schema in pairs(Queue.configuration_fields) do
    if opts[name] ~= nil then
      assert(type(opts[name]) == schema.type,
        name .. " must be a " .. schema.type)
    end
    if opts[name] ~= nil then
      queue[name] = opts[name]
    else
      queue[name] = schema.default
    end
  end

  queue = setmetatable(queue, Queue_mt)

  ngx.timer.at(0, function(_, q)
    q:log(INFO, "starting queue processor")
    while q.running
      and not ngx.worker.exiting()
      and (now() - q.last_used) < q.max_idle_time
    do
      q:log(DEBUG, "processing queue")
      q:process_once(queue.poll_time)
    end
    q:log(INFO, "queue stopped and deleted")
    queues[queue_name] = nil
  end, queue)

  queues[queue_name] = queue

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
  return ngx.log(level, string.format(self.plugin_name .. "." .. self.name .. ": " .. formatstring, unpack({...})))
end


function Queue:delete_frontmost_entry()
  if self.string_capacity then
    self.bytes_queued = self.bytes_queued - #self.queue[1]
  end
  table.remove(self.queue, 1)
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
  while entry_count < self.batch_max_size and (now() - data_started) <= self.max_delay do
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
  while true do
    self:log(DEBUG, "passing %d entries to handler", entry_count)
    self.last_used = now()
    ok, err = self.handler({unpack(self.queue, 1, entry_count)})
    if ok then
      self:log(DEBUG, "handler processed %d entries sucessfully", entry_count)
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

  for _ = 1, entry_count do
    self:delete_frontmost_entry()
  end
  if self.queue_full then
    self:log(INFO, 'queue resumed processing')
    self.queue_full = false
  end
end


-------------------------------------------------------------------------------
-- Drain the queue, for testing purposes.
-- @param self Queue
function Queue:drain()
  self.running = false
  while #self.queue > 0 do
    self:process_once(0.01)
  end
end


-------------------------------------------------------------------------------
-- Add data to the queue
-- @param conf plugin configuration of the plugin instance that caused the item to be queued
-- @param entry the value included in the queue. It can be any Lua value besides nil.
-- @return true, or nil and an error message.
function Queue:add(data)
  -- FIXME check argument types
  if data == nil then
    return nil, "entry must be a non-nil Lua value"
  end

  if #self.queue == self.capacity * 0.9 then
    self:log(WARN, 'queue at 90% capacity')
  end

  if #self.queue == self.capacity then
    if not self.queue_full then
      self.queue_full = true
      self:log(ERR, "queue full, dropping old entries until processing is successful again")
    end
    self:delete_frontmost_entry()
  end

  if self.string_capacity then
    if type(data) ~= "string" then
      self:log(ERR, "queuing non-string data to a queue that has queue.string_capacity set, capacity monitoring will not be correct")
    else
      if #data > self.string_capacity then
        self:log(ERR,
          "string to be queued is longer (%d bytes) than the queue's string_capacity (%d bytes)",
          #data, self.string_capacity)
        return
      end

      local dropped = 0
      while #self.queue > 0 and (self.bytes_queued + #data) > self.string_capacity do
        self:delete_frontmost_entry()
        dropped = dropped + 1
      end
      if dropped > 0 then
        self:log(ERR, "string capacity exceeded, %d queue entries were dropped", dropped)
      end

      self.bytes_queued = self.bytes_queued + #data
    end
  end

  self.last_used = now()
  table.insert(self.queue, data)
  self.semaphore:post()

  return true
end


return Queue
