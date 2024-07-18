-- Batch queue with background retryable processing
--
-- This is a queue of "entries". Entries can be any Lua value.
--
-- Entries are internally organized into batches. The queue has only one mandatory
-- parameter called `process`. This is a function which can consume entries - usually
-- the entries of a batch.
--
-- The purpose of batching is multiple:
--
-- * Batches are retried a number of times, as per configured by the `retry_count` option.
-- * Batches can have a max size, which forces closing the batch and starting a new one.
-- * The processing occurs on a timer-based callback, so it never blocks the current thread.
-- * It is understood that processing a batch can "fail" (return nil). When this happens,
--   batches are "re-queued" a number of times before they are discarded.
--
-- Usage:
--
--   local BatchQueue = require "kong.tools.batch_queue"
--
--   local process = function(entries)
--     -- must return a truthy value if ok, or nil + error otherwise
--     return true
--   end
--
--   local q = BatchQueue.new(
--     process, -- function used to "process/consume" values from the queue
--     { -- Opts table with control values. Defaults shown:
--       retry_count    = 0,    -- number of times to retry processing
--       batch_max_size = 1000, -- max number of entries that can be queued before they are queued for processing
--       process_delay  = 1,    -- in seconds, how often the current batch is closed & queued
--       flush_timeout  = 2,    -- in seconds, how much time passes without activity before the current batch is closed and queued
--     }
--   )
--
--   q:add("Some value")
--   q:add("Some other value")
--
--   ...
--
--   -- Optionally:
--   q:flush()
--
-- Given the example above,
--
-- * Calling `q:flush()` manually "closes" the current batch and queues it for processing.
-- * Since process_delay is 1, the queue will not try to process anything before 0 second passes
-- * Assuming both `add` methods are called within that second, a call to `process` will be scheduled with two entries: {"Some value", "Some other value"}.
-- * If processing fails, it will not be retried (retry_count equals 0)
-- * If retry_count was bigger than 0, processing would be re-queued n times before finally being discarded.
-- * The retries are not regular: every time a process fails, they next retry is delayed by n_try^2, up to 60s.
-- * `flush_timeout` ensures that we don't have old entries queued without processing, by periodically closing the
--   current batch, even when there's no activity.
--
-- The most important internal attributes of Queue are:
--
-- * `self.current_batch`: This is the batch we're currently adding entries to (when using `q:add`)
-- * `self.batch_queue`: This is an array of batches, which are awaiting processing/consumption
--
-- Each batch has the following structure:
--   { retries = 0,                                 -- how many times we have tried to process this node
--     entries = { "some data", "some other data" } -- array of entries. They can be any Lua value
--   }


local setmetatable = setmetatable
local timer_at = ngx.timer.at
local remove = table.remove
local type = type
local huge = math.huge
local fmt = string.format
local min = math.min
local now = ngx.now
local ERR = ngx.ERR
local ngx_log = ngx.log
local DEBUG = ngx.DEBUG
local WARN = ngx.WARN


-- max delay of 60s
local RETRY_MAX_DELAY = 60


local Queue = {}


local Queue_mt = {
  __index = Queue
}


-- Forward function declarations
local flush
local process


-------------------------------------------------------------------------------
-- Create a timer for the `flush` operation.
-- @param self Queue
local function schedule_flush(self)
  local ok, err = timer_at(self.flush_timeout/1000, flush, self)
  if not ok then
    ngx_log(ERR, "failed to create delayed flush timer: ", err)
    return
  end
  --ngx_log(DEBUG, "delayed timer created")
  self.flush_scheduled = true
end


-------------------------------------------------------------------------------
-- Create a timer for the `process` operation.
-- @param self Queue
-- @param batch: table with `entries` and `retries` counter
-- @param delay number: timer delay in seconds
local function schedule_process(self, batch, delay)
  local ok, err = timer_at(delay, process, self, batch)
  if not ok then
    ngx_log(ERR, "failed to create process timer: ", err)
    return
  end
  self.process_scheduled = true
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
-- Timer callback for triggering a queue flush.
-- @param premature boolean: ngx.timer premature indicator
-- @param self Queue
-- @return nothing
flush = function(premature, self)
  if premature then
    return
  end

  if get_now() - self.last_t < self.flush_timeout then
    -- flushing reported: we had activity
    ngx_log(DEBUG, "[flush] queue had activity, delaying flush")
    schedule_flush(self)
    return
  end

  -- no activity and timeout reached
  ngx_log(DEBUG, "[flush] queue had no activity, flushing triggered by flush_timeout")
  self:flush()
  self.flush_scheduled = false
end


-------------------------------------------------------------------------------
-- Timer callback for issuing the `self.process` operation
-- @param premature boolean: ngx.timer premature indicator
-- @param self Queue
-- @param batch: table with `entries` and `retries` counter
-- @return nothing
process = function(premature, self, batch)
  if premature then
    return
  end

  local next_retry_delay

  local ok, err = self.process(batch.entries)
  if ok then -- success, reset retry delays
    self.retry_delay = 1
    next_retry_delay = 0

  else
    batch.retries = batch.retries + 1
    if batch.retries < self.retry_count then
      ngx_log(WARN, "failed to process entries: ", tostring(err))
      -- queue our data for processing again, at the end of the queue
      self.batch_queue[#self.batch_queue + 1] = batch
    else
      ngx_log(ERR, fmt("entry batch was already tried %d times, dropping it",
                   batch.retries))
    end

    self.retry_delay = self.retry_delay + 1
    next_retry_delay = min(RETRY_MAX_DELAY, self.retry_delay * self.retry_delay)
  end

  if #self.batch_queue > 0 then -- more to process?
    ngx_log(DEBUG, fmt("processing oldest data, %d still queued",
                   #self.batch_queue - 1))
    local oldest_batch = remove(self.batch_queue, 1)
    schedule_process(self, oldest_batch, next_retry_delay)
    return
  end

  -- we finished flushing the batch_queue, allow the creation
  -- of a future timer once the current data reached its limit
  -- and we trigger a flush()
  self.process_scheduled = false
end


---------
-- Queue
---------


-------------------------------------------------------------------------------
-- Initialize a batch queue with background retryable processing
-- @param process function, invoked to process every payload generated
-- @param opts table, optionally including
-- `retry_count`, `flush_timeout`, `batch_max_size` and `process_delay`
-- @return table: a Queue object.
function Queue.new(process, opts)
  opts = opts or {}

  assert(type(process) == "function",
         "arg #1 (process) must be a function")
  assert(type(opts) == "table",
         "arg #2 (opts) must be a table")
  assert(opts.retry_count == nil or type(opts.retry_count) == "number",
         "retry_count must be a number")
  assert(opts.flush_timeout == nil or type(opts.flush_timeout) == "number",
         "flush_timeout must be a number")
  assert(opts.batch_max_size == nil or type(opts.batch_max_size) == "number",
         "batch_max_size must be a number")
  assert(opts.process_delay == nil or type(opts.batch_max_size) == "number",
         "process_delay must be a number")

  local self = {
    process = process,

    -- flush timeout in milliseconds
    flush_timeout = opts.flush_timeout and opts.flush_timeout * 1000 or 2000,
    retry_count = opts.retry_count or 0,
    batch_max_size = opts.batch_max_size or 1000,
    process_delay = opts.process_delay or 1,

    retry_delay = 1,

    batch_queue = {},
    current_batch = { entries = {}, count = 0, retries = 0 },

    flush_scheduled = false,
    process_scheduled = false,

    last_t = huge,
  }

  return setmetatable(self, Queue_mt)
end


-------------------------------------------------------------------------------
-- Add data to the queue
-- @param entry the value included in the queue. It can be any Lua value besides nil.
-- @return true, or nil and an error message.
function Queue:add(entry)
  if entry == nil then
    return nil, "entry must be a non-nil Lua value"
  end

  if self.batch_max_size == 1 then
    -- no batching
    local batch = { entries = { entry }, retries = 0 }
    schedule_process(self, batch, 0)
    return true
  end

  local cb = self.current_batch
  local new_size = #cb.entries + 1
  cb.entries[new_size] = entry

  if new_size >= self.batch_max_size then
    local ok, err = self:flush()
    if not ok then
      return nil, err
    end

  elseif not self.flush_scheduled then
    schedule_flush(self)
  end

  self.last_t = get_now()

  return true
end


-------------------------------------------------------------------------------
-- * Close the current batch and place it the processing queue
-- * Start a new empty batch
-- * Schedule processing if needed.
-- @return true, or nil and an error message.
function Queue:flush()
  local current_batch_size = #self.current_batch.entries

  -- Queue the current batch, if it has at least 1 entry
  if current_batch_size > 0 then
    ngx_log(DEBUG, "queueing batch for processing (", current_batch_size, " entries)")

    self.batch_queue[#self.batch_queue + 1] = self.current_batch
    self.current_batch = { entries = {}, retries = 0 }
  end

  -- Then, if there are batches queued for processing, schedule a process
  -- in the future. This will keep calling itself in the future until
  -- the queue is empty
  if #self.batch_queue > 0 and not self.process_scheduled then
    ngx_log(DEBUG, fmt("processing oldest entry, %d still queued",
                       #self.batch_queue - 1))
    local oldest_batch = remove(self.batch_queue, 1)
    schedule_process(self, oldest_batch, self.process_delay)
  end

  return true
end


return Queue
