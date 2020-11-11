local semaphore = require "ngx.semaphore"


local ngx = ngx
local kong = kong
local math = math
local type = type
local pcall = pcall
local table = table
local string = string
local select = select
local unpack = unpack
local assert = assert
local setmetatable = setmetatable


local TIMER_INTERVAL = 0.1
local WAIT_INTERVAL  = 0.5
local LOG_INTERVAL   = 60
local BUCKET_SIZE    = 1000
local LAWN_SIZE      = 10000
local QUEUE_SIZE     = 100000


local DELAYS = {
  second = 1,
  minute = 60,
  hour   = 3600,
  day    = 86400,
  week   = 604800,
  month  = 2629743.833,
  year   = 31556926,
}


local function get_pending(queue, size)
  local head = queue.head
  local tail = queue.tail
  if head < tail then
    head = head + size
  end
  return head - tail
end


local function job_thread(self, index)
  while true do
    local ok, err = self.work:wait(WAIT_INTERVAL)
    if ok then
      local tail = self.tail == QUEUE_SIZE and 1 or self.tail + 1
      local job = self.jobs[tail]
      self.tail = tail
      self.jobs[tail] = nil
      self.running = self.running + 1
      self.time[tail][2] = ngx.now() * 1000
      ok, err = job()
      self.time[tail][3] = ngx.now() * 1000
      self.running = self.running - 1
      self.done = self.done + 1
      if not ok then
        self.errored = self.errored + 1
        kong.log.err("async thread #", index, " job error: ", err)
      end

    elseif err ~= "timeout" then
      kong.log.err("async thread #", index, " wait error: ", err)
    end

    if self.head == self.tail and (self.aborted > 0 or ngx.worker.exiting()) then
      break
    end
  end

  return true
end


local function log_timer(premature, self)
  if premature then
    return true
  end

  local debug  = QUEUE_SIZE / 10000
  local info   = QUEUE_SIZE / 1000
  local notice = QUEUE_SIZE / 100
  local warn   = QUEUE_SIZE / 10
  local err    = QUEUE_SIZE

  local pending = get_pending(self, QUEUE_SIZE)

  local msg = string.format("async jobs: %u running, %u pending, %u errored, %u refused, %u done",
                            self.running, pending, self.errored, self.refused, self.done)
  if pending <= debug then
    kong.log.debug(msg)
  elseif pending <= info then
    kong.log.info(msg)
  elseif pending <= notice then
    kong.log.notice(msg)
  elseif pending < warn then
    kong.log.warn(msg)
  elseif pending < err then
    kong.log.err(msg)
  else
    kong.log.crit(msg)
  end

  return true
end


local function job_timer(premature, self)
  if premature then
    return true
  end

  local t = kong.table.new(100, 0)

  for i = 1, 100 do
    t[i] = ngx.thread.spawn(job_thread, self, i)
  end

  local ok, err = ngx.thread.wait(t[1],  t[2],  t[3],  t[4],  t[5],  t[6],  t[7],  t[8],  t[9],  t[10],
                                  t[11], t[12], t[13], t[14], t[15], t[16], t[17], t[18], t[19], t[20],
                                  t[21], t[22], t[23], t[24], t[25], t[26], t[27], t[28], t[29], t[30],
                                  t[31], t[32], t[33], t[34], t[35], t[36], t[37], t[38], t[39], t[40],
                                  t[41], t[42], t[43], t[44], t[45], t[46], t[47], t[48], t[49], t[50],
                                  t[51], t[52], t[53], t[54], t[55], t[56], t[57], t[58], t[59], t[60],
                                  t[61], t[62], t[63], t[64], t[65], t[66], t[67], t[68], t[69], t[70],
                                  t[71], t[72], t[73], t[74], t[75], t[76], t[77], t[78], t[79], t[80],
                                  t[81], t[82], t[83], t[84], t[85], t[86], t[87], t[88], t[89], t[90],
                                  t[91], t[92], t[93], t[94], t[95], t[96], t[97], t[98], t[99], t[100])

  if not ok then
    kong.log.err("async thread error: ", err)
  end

  for i = 100, 1, -1 do
    ngx.thread.kill(t[i])
  end

  return job_timer(ngx.worker.exiting(), self)
end


local function every_timer(_, self, delay)
  local bucket = self.buckets[delay]
  for i = 1, bucket.head do
    local ok, err = bucket.jobs[i](self)
    if not ok then
      kong.log.err(err)
    end
  end

  return true
end


local function at_timer(premature, self)

  -- DO NOT YIELD IN THIS FUNCTION AS IT IS EXECUTED FREQUENTLY!

  if self.lawn.head == self.lawn.tail then
    return true
  end

  local now = premature and math.huge or ngx.now()
  if self.closest > now then
    return true
  end

  local lawn    = self.lawn
  local ttls    = lawn.ttls
  local buckets = lawn.buckets

  local head = lawn.head
  local tail = lawn.tail
  while head ~= tail do
    tail = tail == LAWN_SIZE and 1 or tail + 1
    local ttl = ttls[tail]
    local bucket = buckets[ttl]
    if bucket.head == bucket.tail then
      lawn.tail = lawn.tail == LAWN_SIZE and 1 or lawn.tail + 1
      buckets[ttl] = nil
      ttls[tail] = nil

    else
      local ok = true
      local err
      while bucket.head ~= bucket.tail do
        local bucket_tail = bucket.tail == BUCKET_SIZE and 1 or bucket.tail + 1
        local expiry = bucket.jobs[bucket_tail][1]
        if expiry >= now then
          break
        end

        ok, err = bucket.jobs[bucket_tail][2](self)
        if not ok then
          break
        end

        bucket.jobs[bucket_tail] = nil
        bucket.tail = bucket_tail

        if self.closest == 0 or self.closest > expiry then
          self.closest = expiry
        end
      end

      lawn.tail = lawn.tail == LAWN_SIZE and 1 or lawn.tail + 1
      lawn.head = lawn.head == LAWN_SIZE and 1 or lawn.head + 1
      ttls[lawn.head] = ttl
      ttls[tail] = nil

      if not ok then
        kong.log:err(err)
        return
      end
    end
  end

  return true
end


local function create_job(func, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, ...)
  local argc = select("#", ...)
  local args = argc > 0 and { ... }

  if not args then
    return function()
      return pcall(func, ngx.worker.exiting(), a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
    end
  end

  return function()
    local pok, res, err = pcall(func, ngx.worker.exiting(), a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, unpack(args, 1, argc))
    if not pok then
      return nil, res
    end

    if not err then
      return true
    end

    return nil, err
  end
end


local function queue_job(self, is_job, func, ...)
  if get_pending(self, QUEUE_SIZE) == QUEUE_SIZE then
    self.refused = self.refused + 1
    return nil, "async queue is full"
  end

  self.head = self.head == QUEUE_SIZE and 1 or self.head + 1
  self.jobs[self.head] = is_job and func or create_job(func, ...)
  self.time[self.head][1] = ngx.now() * 1000
  self.work:post()

  return true
end


local function create_recurring_job(job)
  local running = false

  local recurring_job = function()
    running = true
    local ok, err = job()
    running = false
    return ok, err
  end

  return function(self)
    if running then
      return nil, "recurring job is already running"
    end

    return queue_job(self, true, recurring_job)
  end
end


local function create_at_job(job)
  return function(self)
    return queue_job(self, true, job)
  end
end


local function get_stats(self, from, to)
  local data, size = self:data(from, to)
  local names = { "max", "min", "mean", "median", "p95", "p99", "p999" }
  local stats = kong.table.new(2, 0)

  for i = 1, 2 do
    stats[i] = kong.table.new(0, #names + 1)
    stats[i].size = size
    if size == 0 then
      for j = 1, #names do
        stats[i][names[j]] = 0
      end

    elseif size == 1 then
      local time = i == 1 and data[1][2] - data[1][1]
                           or data[1][3] - data[1][2]

      for j = 1, #names do
        stats[i][names[j]] = time
      end

    elseif size > 1 then
      local tot = 0
      local raw = kong.table.new(size, 0)
      local max
      local min

      for j = 1, size do
        local time = i == 1 and data[j][2] - data[j][1]
                             or data[j][3] - data[j][2]
        raw[j] = time
        tot = tot + time
        max = math.max(time, max or time)
        min = math.min(time, min or time)
      end

      stats[i].max = max
      stats[i].min = min
      stats[i].mean = math.floor(tot / size + 0.5)

      table.sort(raw)

      local n = { "median", "p95", "p99", "p999" }
      local m = { 0.5, 0.95, 0.99, 0.999 }

      for j = 1, #n do
        local idx = size * m[j]
        if idx == math.floor(idx) then
          stats[i][n[j]] = math.floor((raw[idx] + raw[idx + 1]) / 2 + 0.5)
        else
          stats[i][n[j]] = raw[math.floor(idx + 0.5)]
        end
      end
    end
  end

  return {
    latency = stats[1],
    runtime = stats[2],
  }
end


local async = {}
async.__index = async


---
-- Creates a new instance of `kong.async`
--
-- @treturn table an instance of `kong.async`
function async.new()
  local time = kong.table.new(QUEUE_SIZE, 0)
  for i = 1, QUEUE_SIZE do
    time[i] = kong.table.new(3, 0)
  end

  return setmetatable({
    jobs = kong.table.new(QUEUE_SIZE, 0),
    time = time,
    work = semaphore.new(),
    lawn = {
      head    = 0,
      tail    = 0,
      ttls    = kong.table.new(LAWN_SIZE, 0),
      buckets = {},
    },
    buckets = {},
    closest = 0,
    running = 0,
    errored = 0,
    refused = 0,
    done = 0,
    head = 0,
    tail = 0,
  }, async)
end


---
-- Start `kong.async` timers
--
-- @treturn boolean|nil `true` on success, `nil` on error
-- @treturn string|nil  `nil` on success, error message `string` on error
function async:start()
  if ngx.worker.exiting() then
    return nil, "nginx worker is exiting"
  end

  local ok, err = ngx.timer.at(0, job_timer, self)
  if not ok then
    return nil, err
  end

  ok, err = ngx.timer.every(TIMER_INTERVAL, at_timer, self)
  if not ok then
    return nil, err
  end

  ok, err = ngx.timer.every(LOG_INTERVAL, log_timer, self)
  if not ok then
    return nil, err
  end

  return true
end


---
-- Run a function asynchronously
--
-- @tparam  function   a function to run asynchronously
-- @tparam  ...[opt]   function arguments
-- @treturn true|nil   `true` on success, `nil` on error
-- @treturn string|nil `nil` on success, error message `string` on error
function async:run(func, ...)
  if ngx.worker.exiting() then
    return nil, "nginx worker is exiting"
  end

  return queue_job(self, false, func, ...)
end


---
-- Run a function asynchronously and repeatedly but non-overlapping
--
-- @tparam  number|string function execution interval (a non-zero positive number
--                        or `"second"`, `"minute"`, `"hour"`, `"month" or `"year"`)
-- @tparam  function      a function to run asynchronously
-- @tparam  ...[opt]      function arguments
-- @treturn true|nil      `true` on success, `nil` on error
-- @treturn string|nil    `nil` on success, error message `string` on error
function async:every(delay, func, ...)
  if ngx.worker.exiting() then
    return nil, "nginx worker is exiting"
  end

  delay = DELAYS[delay] or delay

  assert(type(delay) == "number" and delay > 0, "invalid delay, must be a number greater than zero or " ..
                                                "'second', 'minute', 'hour', 'month' or 'year'")

  local bucket = self.buckets[delay]
  if bucket then
    if bucket.head == BUCKET_SIZE then
      self.refused = self.refused + 1
      return nil, "async bucket (" .. delay .. ") is full"
    end

  else
    local ok, err = ngx.timer.every(delay, every_timer, self, delay)
    if not ok then
      return nil, err
    end

    bucket = {
      jobs = kong.table.new(BUCKET_SIZE, 0),
      head = 0,
    }

    self.buckets[delay] = bucket
  end

  bucket.head = bucket.head + 1
  bucket.jobs[bucket.head] = create_recurring_job(create_job(func, ...))

  return true
end


---
-- Run a function asynchronously with a specific delay
--
-- @tparam  number|string function execution delay (a positive number, zero included,
--                        or `"second"`, `"minute"`, `"hour"`, `"month" or `"year"`)
-- @tparam  function      a function to run asynchronously
-- @tparam  ...[opt]      function arguments
-- @treturn true|nil      `true` on success, `nil` on error
-- @treturn string|nil    `nil` on success, error message `string` on error
function async:at(delay, func, ...)
  if ngx.worker.exiting() then
    return nil, "nginx worker is exiting"
  end

  delay = DELAYS[delay] or delay

  assert(type(delay) == "number" and delay >= 0, "invalid delay, must be a positive number or " ..
                                                 "'second', 'minute', 'hour', 'month' or 'year'")

  if delay == 0 then
    return queue_job(self, false, func, ...)
  end

  local lawn = self.lawn
  if get_pending(lawn, LAWN_SIZE) == LAWN_SIZE then
    self.refused = self.refused + 1
    return nil, "async lawn (" .. delay .. ") is full"
  end

  local bucket = lawn.buckets[delay]
  if bucket then
    if get_pending(bucket, BUCKET_SIZE) == BUCKET_SIZE then
      self.refused = self.refused + 1
      return nil, "async bucket (" .. delay .. ") is full"
    end

  else
    lawn.head = lawn.head == LAWN_SIZE and 1 or lawn.head + 1
    lawn.ttls[lawn.head] = delay

    bucket = {
      jobs = kong.table.new(BUCKET_SIZE, 0),
      head = 0,
      tail = 0,
    }

    lawn.buckets[delay] = bucket
  end

  local expiry = ngx.now() + delay

  bucket.head = bucket.head == BUCKET_SIZE and 1 or bucket.head + 1
  bucket.jobs[bucket.head] = {
    expiry,
    create_at_job(create_job(func, ...)),
  }

  self.closest = math.min(self.closest, expiry)

  return true
end


---
-- Kong async raw metrics data
--
-- @tparam  from[opt]  data start time (from unix epoch)
-- @tparam  to[opt]    data end time (from unix epoch)
-- @treturn table      a table containing the metrics
-- @treturn number     number of metrics returned
function async:data(from, to)
  local time = self.time
  local done = math.min(self.done, QUEUE_SIZE)
  if not from and not to then
    return time, done
  end

  from = from and from * 1000 or 0
  to   = to   and to   * 1000 or math.huge

  local data = kong.table.new(done, 0)
  local size = 0
  for i = 1, done do
    if time[i][1] >= from and time[i][3] <= to then
      size = size + 1
      data[size] = time[i]
    end
  end

  return data, size
end


---
-- Return statistics
--
-- @tparam  opts[opt] data start time (from unix epoch)
-- @treturn table     a table containing calculated statistics
function async:stats(opts)
  local stats
  local pending = get_pending(self, QUEUE_SIZE)
  if not opts then
    stats = get_stats(self)
    stats.done    = self.done
    stats.pending = pending
    stats.running = self.running
    stats.errored = self.errored
    stats.refused = self.refused

  else
    local now = ngx.now()

    local all    = opts.all    and get_stats(self)
    local minute = opts.minute and get_stats(self, now - DELAYS.minute)
    local hour   = opts.hour   and get_stats(self, now - DELAYS.hour)

    local latency
    local runtime
    if all or minute or hour then
      latency = {
        all    = all    and all.latency,
        minute = minute and minute.latency,
        hour   = hour   and hour.latency,
      }
      runtime = {
        all    = all    and all.runtime,
        minute = minute and minute.runtime,
        hour   = hour   and hour.runtime,
      }
    end

    stats = {
      done    = self.done,
      pending = pending,
      running = self.running,
      errored = self.errored,
      refused = self.refused,
      latency = latency,
      runtime = runtime,
    }
  end

  return stats
end


return async
