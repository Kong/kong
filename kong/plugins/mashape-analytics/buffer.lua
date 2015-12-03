-- ALF buffer module
--
-- This module contains a buffered array of ALF objects. When the buffer is full (max number of entries
-- or max payload size accepted by the collector), it is eventually converted to a JSON payload and moved a
-- queue of payloads to be sent to the server. "Eventually", because to prevent the sending queue from growing
-- too much and crashing the Lua VM, its size is limited (in bytes). If the sending queue is currently bloated
-- and reached its size limit, then the buffer is NOT added to it, and simply discarded. ALFs will be lost.
--
-- So to resume:
--   One buffer of ALFs (gets flushed once it reaches the max size)
--   One queue of pending, ready-to-be-sent batches which are JSON payloads (which also has a max size, in bytes)
--
-- 1. The sending queue keeps sending batches one by one, and if batches are acknowledged by the collector,
-- the batch is considered saved and is discarded.
-- 2. If the batch is invalid (bad ALF formatting) according to the collector, it is discarded and won't be retried.
-- 3. If the connection to the collector could not be made, the batch will not be discarded so it can be retried.
-- 4. The sending queue keeps sending batches as long as it has some pending for sending. If the connection failed (3.),
-- the sending queue will use a retry policy timer which is incremented everytime the collector did not answer.
-- 5. We run a 'delayed timer' in case no call is received for a while to still flush the buffer and have 'real-time' analytics.
--
-- @see alf_serializer.lua
-- @see handler.lua

local json = require "cjson"
local http = require "resty_http"

local table_getn = table.getn
local ngx_now = ngx.now
local ngx_log = ngx.log
local ngx_log_ERR = ngx.ERR
local ngx_timer_at = ngx.timer.at
local table_insert = table.insert
local table_concat = table.concat
local table_remove = table.remove
local string_sub = string.sub
local string_len = string.len
local string_rep = string.rep
local string_format = string.format
local math_pow = math.pow
local math_min = math.min
local setmetatable = setmetatable

local MB = 1024 * 1024
local MAX_COLLECTOR_PAYLOAD_SIZE = 500 * MB
local EMPTY_ARRAY_PLACEHOLDER = "__empty_array_placeholder__"

-- Define an exponential retry policy for all workers.
-- The policy will give a delay that grows everytime
-- Galileo fails to respond. As soon as Galileo responds,
-- the delay is reset to its base.
local dict = ngx.shared.locks
local RETRY_INDEX_KEY = "mashape_analytics_retry_index"
local RETRY_BASE_DELAY = 1 -- seconds
local RETRY_MAX_DELAY = 60 -- seconds

local buffer_mt = {}
buffer_mt.__index = buffer_mt
buffer_mt.MAX_COLLECTOR_PAYLOAD_SIZE = MAX_COLLECTOR_PAYLOAD_SIZE

-- A handler for delayed batch sending. When no call has been made for X seconds
-- (X being conf.delay), we send the batch to keep analytics as close to real-time
-- as possible.
local delayed_send_handler
delayed_send_handler = function(premature, buffer)
  if ngx_now() - buffer.latest_call < buffer.auto_flush_delay then
    -- If the latest call was received during the wait delay, abort the delayed send and
    -- report it for X more seconds.
    local ok, err = ngx_timer_at(buffer.auto_flush_delay, delayed_send_handler, buffer)
    if not ok then
      buffer.lock_delayed = false -- re-enable creation of a delayed-timer for this buffer
      ngx_log(ngx_log_ERR, "[mashape-analytics] failed to create delayed batch sending timer: ", err)
    end
  else
    -- Buffer is not full but it's been too long without an API call, let's flush it
    -- and send the data to analytics.
    buffer:flush()
    buffer.lock_delayed = false
    buffer.send_batch(nil, buffer)
  end
end

-- Instanciate a new buffer with configuration and properties
function buffer_mt.new(conf)
  local buffer = {
    max_entries = conf.batch_size,
    auto_flush_delay = conf.delay,
    host = conf.host,
    port = conf.port,
    path = conf.path,
    max_sending_queue_size = conf.max_sending_queue_size * MB,
    entries = {}, -- current buffer as an array of strings (serialized ALFs)
    entries_size = 0, -- current entries size in bytes (total)
    sending_queue = {}, -- array of constructed payloads (batches of ALFs) to be sent
    sending_queue_size = 0, -- current sending queue size in bytes
    lock_sending = false, -- lock if currently sending its data
    lock_delayed = false, -- lock if a delayed timer is already set for this buffer
    latest_call = nil -- date at which a request was last made to this API (for the delayed timer to know if it needs to trigger)
  }
  return setmetatable(buffer, buffer_mt)
end

-- Add an ALF (already serialized) to the buffer
-- If the buffer is full (max entries or size in bytes), convert the buffer
-- to a JSON payload and place it in an array to be sent, then trigger a sending.
-- If the buffer is not full, start a delayed timer in case no call is received
-- for a while.
function buffer_mt:add_alf(alf)
  -- Keep track of the latest call for the delayed timer
  self.latest_call = ngx_now()

  local str = json.encode(alf)
  str = str:gsub("\""..EMPTY_ARRAY_PLACEHOLDER.."\"", ""):gsub("\\/", "/")

  -- Check what would be the size of the buffer
  local next_n_entries = table_getn(self.entries) + 1
  local alf_size = string_len(str)

  -- If the alf_size exceeds the payload limit by itself, we have a big problem
  if alf_size > buffer_mt.MAX_COLLECTOR_PAYLOAD_SIZE then
    ngx_log(ngx_log_ERR, string_format("[mashape-analytics] ALF size exceeds the maximum size (%sMB) accepted by the collector. Dropping it.", buffer_mt.MAX_COLLECTOR_PAYLOAD_SIZE / MB))
    return
  end

  -- If size or entries exceed the max limits
  local full = next_n_entries > self.max_entries or (self:get_size() + alf_size) > buffer_mt.MAX_COLLECTOR_PAYLOAD_SIZE
  if full then
    self:flush()
    -- Batch size reached, let's send the data
    local ok, err = ngx_timer_at(0, self.send_batch, self)
    if not ok then
      ngx_log(ngx_log_ERR, "[mashape-analytics] failed to create batch sending timer: ", err)
    end
  elseif not self.lock_delayed then
    -- Batch size not yet reached.
    -- Set a timer sending the data only in case nothing happens for awhile or if the batch_size is taking
    -- too much time to reach the limit and trigger the flush.
    local ok, err = ngx_timer_at(self.auto_flush_delay, delayed_send_handler, self)
    if ok then
      self.lock_delayed = true -- Make sure only one delayed timer is ever pending for a given buffer
    else
      ngx_log(ngx_log_ERR, "[mashape-analytics] failed to create delayed batch sending timer: ", err)
    end
  end

  -- Insert in entries
  table_insert(self.entries, str)
  -- Update current buffer size
  self.entries_size = self.entries_size + alf_size
end

-- Build a JSON payload of the current buffer.
function buffer_mt:payload_string()
  return "["..table_concat(self.entries, ",").."]"
end

-- Get the size of the current buffer if it was to be converted to a JSON payload
function buffer_mt:get_size()
  local commas = string_rep(",", table_getn(self.entries) - 1)
  return string_len(commas.."[]") + self.entries_size
end

-- Flush the buffer
-- 1. Make sure the batch is not too big for the configured max_sending_queue_size
-- 2. Make sure the current sending queue doesn't exceed its size limit
-- 2b. Convert its content into a JSON payload
-- 2c. Add the payload to the queue of payloads to be sent
-- 3. Empty the buffer and reset the current buffer size
function buffer_mt:flush()
  local batch_size = self:get_size()

  if batch_size > self.max_sending_queue_size then
    ngx_log(ngx.NOTICE, string_format("[mashape-analytics] batch was bigger (%s bytes) than the configured max_sending_queue_size (%s bytes). Dropping it (%s ALFs)", batch_size, self.max_sending_queue_size, table_getn(self.entries)))
  elseif self.sending_queue_size + batch_size <= self.max_sending_queue_size then
    self.sending_queue_size = self.sending_queue_size + batch_size

    table_insert(self.sending_queue, {
      payload = self:payload_string(),
      n_entries = table_getn(self.entries),
      size = batch_size
    })
  else
    ngx_log(ngx.NOTICE, string_format("[mashape-analytics] buffer reached its maximum max_sending_queue_size. (%s) ALFs, (%s) bytes dropped.", table_getn(self.entries), batch_size))
  end

  self.entries = {}
  self.entries_size = 0
end

-- Send the oldest payload (batch of ALFs) from the queue to the collector.
-- The payload will be removed if the collector acknowledged the batch.
-- If the queue still has payloads to be sent, keep on sending them.
-- If the connection to the collector fails, use the retry policy.
function buffer_mt.send_batch(premature, self)
  if self.lock_sending then return end
  self.lock_sending = true -- simple lock

  if table_getn(self.sending_queue) < 1 then
    return
  end

  -- Let's send the oldest batch in our queue
  local batch_to_send = table_remove(self.sending_queue, 1)

  local retry
  local client = http:new()
  client:set_timeout(5000) -- 5 sec

  local ok, err = client:connect(self.host, self.port)
  if ok then
    local res, err = client:request({path = self.path, body = batch_to_send.payload})
    if not res then
      retry = true
      ngx_log(ngx_log_ERR, string_format("[mashape-analytics] failed to send batch (%s ALFs %s bytes): %s", batch_to_send.n_entries, batch_to_send.size, err))
    else
      res.body = string_sub(res.body, 1, -2) -- remove trailing line jump for logs
      if res.status == 200 then
        ngx_log(ngx.DEBUG, string_format("[mashape-analytics] successfully saved the batch. (%s)", res.body))
      elseif res.status == 207 then
        ngx_log(ngx_log_ERR, string_format("[mashape-analytics] collector could not save all ALFs from the batch. (%s)", res.body))
      elseif res.status == 400 then
        ngx_log(ngx_log_ERR, string_format("[mashape-analytics] collector refused the batch (%s ALFs %s bytes). Dropping batch. Status: (%s) Error: (%s)", batch_to_send.n_entries, batch_to_send.size, res.status, res.body))
      else
        retry = true
        ngx_log(ngx_log_ERR, string_format("[mashape-analytics] collector could not save the batch (%s ALFs %s bytes). Status: (%s) Error: (%s)", batch_to_send.n_entries, batch_to_send.size, res.status, res.body))
      end
    end

    -- close connection, or put it into the connection pool
    if not res or res.headers["connection"] == "close" then
      ok, err = client:close()
      if not ok then
        ngx_log(ngx_log_ERR, "[mashape-analytics] failed to close socket: ", err)
      end
    else
      client:set_keepalive()
    end
  else
    retry = true
    ngx_log(ngx_log_ERR, "[mashape-analytics] failed to connect to the collector: ", err)
  end

  local next_batch_delay = 0 -- default delay for the next batch sending

  if retry then
    -- could not reach the collector, need to retry
    table_insert(self.sending_queue, 1, batch_to_send)

    local ok, err = dict:add(RETRY_INDEX_KEY, 0)
    if not ok and err ~= "exists" then
      ngx_log(ngx_log_ERR, "[mashape-analytics] cannot prepare retry policy: ", err)
    end

    local index, err = dict:incr(RETRY_INDEX_KEY, 1)
    if err then
      ngx_log(ngx_log_ERR, "[mashape-analytics] cannot increment retry policy index: ", err)
    elseif index then
      next_batch_delay = math_min(math_pow(index, 2) * RETRY_BASE_DELAY, RETRY_MAX_DELAY)
    end

    ngx_log(ngx.NOTICE, string_format("[mashape-analytics] batch was queued for retry. Next retry in: %s seconds", next_batch_delay))
  else
    -- batch acknowledged by the collector
    self.sending_queue_size = self.sending_queue_size - batch_to_send.size

    -- reset retry policy
    local ok, err = dict:set(RETRY_INDEX_KEY, 0)
    if not ok then
      ngx_log(ngx_log_ERR, "[mashape-analytics] cannot reset retry policy index: ", err)
    end
  end

  self.lock_sending = false

  -- Keep sendind data if the queue is not yet emptied
  if table_getn(self.sending_queue) > 0 then
    local ok, err = ngx_timer_at(next_batch_delay, self.send_batch, self)
    if not ok then
      ngx_log(ngx_log_ERR, "[mashape-analytics] failed to create batch retry timer: ", err)
    end
  end
end

return buffer_mt
