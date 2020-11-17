local semaphore = require "ngx.semaphore"


local ngx = ngx
local log = ngx.log
local now = ngx.now
local wait = ngx.thread.wait
local kill = ngx.thread.kill
local spawn = ngx.thread.spawn
local exiting = ngx.worker.exiting
local timer_at = ngx.timer.at
local timer_every = ngx.timer.every
local fmt = string.format
local sort = table.sort
local math = math
local min = math.min
local max = math.max
local huge = math.huge
local floor = math.floor
local type = type
local traceback = debug.traceback
local xpcall = xpcall
local select = select
local unpack = unpack
local assert = assert
local setmetatable = setmetatable


local DEBUG  = ngx.DEBUG
local INFO   = ngx.INFO
local NOTICE = ngx.NOTICE
local ERR    = ngx.ERR
local WARN   = ngx.WARN
local CRIT   = ngx.CRIT


local TIMER_INTERVAL = 0.1
local WAIT_INTERVAL  = 0.5
local LOG_INTERVAL   = 60
local THREADS        = 100
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


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function ()
      return {}
    end
  end
end


local function job_thread(self, index)
  local wait_interval = self.opts.wait_interval
  local queue_size = self.opts.queue_size
  while true do
    local ok, err = self.work:wait(wait_interval)
    if ok then
      local tail = self.tail == queue_size and 1 or self.tail + 1
      local job = self.jobs[tail]
      self.tail = tail
      self.jobs[tail] = nil
      self.running = self.running + 1
      self.time[tail][2] = now() * 1000
      ok, err = job()
      self.time[tail][3] = now() * 1000
      self.running = self.running - 1
      self.done = self.done + 1
      if not ok then
        self.errored = self.errored + 1
        log(ERR, "async thread #", index, " job error: ", err)
      end

    elseif err ~= "timeout" then
      log(ERR, "async thread #", index, " wait error: ", err)
    end

    if self.head == self.tail and (self.aborted > 0 or exiting()) then
      break
    end
  end

  return true
end


local function log_timer(premature, self)
  if premature then
    return true
  end

  local queue_size = self.opts.queue_size

  local dbg = queue_size / 10000
  local nfo = queue_size / 1000
  local ntc = queue_size / 100
  local wrn = queue_size / 10
  local err = queue_size

  local pending = get_pending(self, queue_size)

  local msg = fmt("async jobs: %u running, %u pending, %u errored, %u refused, %u aborted, %u done",
                  self.running, pending, self.errored, self.refused, self.aborted, self.done)
  if pending <= dbg then
    log(DEBUG, msg)
  elseif pending <= nfo then
    log(INFO, msg)
  elseif pending <= ntc then
    log(NOTICE, msg)
  elseif pending < wrn then
    log(WARN, msg)
  elseif pending < err then
    log(ERR, msg)
  else
    log(CRIT, msg)
  end

  return true
end


local function job_timer(premature, self)
  if premature then
    return true
  end

  local t = self.threads

  for i = 1, self.opts.threads do
    t[i] = spawn(job_thread, self, i)
  end

  for i = 1, self.opts.threads do
    local ok, err = wait(t[i])
    if not ok then
      log(ERR, "async thread error: ", err)
    end

    if not exiting() then
      log(CRIT, "async thread #", i, " aborted")
    end

    kill(t[i])
    t[i] = nil

    self.aborted = self.aborted + 1
  end

  if not exiting() then
    log(CRIT, "async threads aborted")
    return
  end

  return true
end


local function every_timer(_, self, delay)
  local bucket = self.buckets[delay]
  for i = 1, bucket.head do
    local ok, err = bucket.jobs[i](self)
    if not ok then
      log(ERR, err)
    end
  end

  return true
end


local function at_timer(premature, self)

  -- DO NOT YIELD IN THIS FUNCTION AS IT IS EXECUTED FREQUENTLY!

  if self.lawn.head == self.lawn.tail then
    return true
  end

  local current_time = premature and huge or now()
  if self.closest > current_time then
    return true
  end

  local lawn        = self.lawn
  local lawn_size   = self.opts.lawn_size
  local bucket_size = self.opts.bucket_size
  local ttls        = lawn.ttls
  local buckets     = lawn.buckets

  local head = lawn.head
  local tail = lawn.tail
  while head ~= tail do
    tail = tail == lawn_size and 1 or tail + 1
    local ttl = ttls[tail]
    local bucket = buckets[ttl]
    if bucket.head == bucket.tail then
      lawn.tail = lawn.tail == lawn_size and 1 or lawn.tail + 1
      buckets[ttl] = nil
      ttls[tail] = nil

    else
      local ok = true
      local err
      while bucket.head ~= bucket.tail do
        local bucket_tail = bucket.tail == bucket_size and 1 or bucket.tail + 1
        local expiry = bucket.jobs[bucket_tail][1]
        if expiry >= current_time then
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

      lawn.tail = lawn.tail == lawn_size and 1 or lawn.tail + 1
      lawn.head = lawn.head == lawn_size and 1 or lawn.head + 1
      ttls[lawn.head] = ttl
      ttls[tail] = nil

      if not ok then
        log(ERR, err)
        return
      end
    end
  end

  return true
end


local function create_job(func, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, ...)
  local argc = select("#", ...)
  if argc == 0 then
    return function()
      return xpcall(func, traceback, exiting(),
                    a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
    end
  end

  local args = { ... }
  return function()
    local pok, res, err = xpcall(func, traceback, exiting(),
                                 a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
                                 unpack(args, 1, argc))
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
  local queue_size = self.opts.queue_size
  if get_pending(self, queue_size) == queue_size then
    self.refused = self.refused + 1
    return nil, "async queue is full"
  end

  self.head = self.head == queue_size and 1 or self.head + 1
  self.jobs[self.head] = is_job and func or create_job(func, ...)
  self.time[self.head][1] = now() * 1000
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
  local stats = new_tab(2, 0)

  for i = 1, 2 do
    stats[i] = new_tab(0, #names + 1)
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
      local raw = new_tab(size, 0)
      local max_value
      local min_value

      for j = 1, size do
        local time = i == 1 and data[j][2] - data[j][1]
                             or data[j][3] - data[j][2]
        raw[j] = time
        tot = tot + time
        max_value = max(time, max_value or time)
        min_value = min(time, min_value or time)
      end

      stats[i].max = max_value
      stats[i].min = min_value
      stats[i].mean = floor(tot / size + 0.5)

      sort(raw)

      local n = { "median", "p95", "p99", "p999" }
      local m = { 0.5, 0.95, 0.99, 0.999 }

      for j = 1, #n do
        local idx = size * m[j]
        if idx == floor(idx) then
          stats[i][n[j]] = floor((raw[idx] + raw[idx + 1]) / 2 + 0.5)
        else
          stats[i][n[j]] = raw[floor(idx + 0.5)]
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
-- Creates a new instance of `resty.async`
--
-- @tparam  options[opt] a table containing options, the following options can be used:
--                       - `timer_interval` (the default is `0.1`)
--                       - `wait_interval`  (the default is `0.5`)
--                       - `log_interval`   (the default is `60`)
--                       - `threads`        (the default is `100`)
--                       - `bucket_size`    (the default is `1000`)
--                       - `lawn_size`      (the default is `10000`)
--                       - `queue_size`     (the default is `100000`)
-- @treturn table        an instance of `resty.async`
function async.new(options)
  assert(options == nil or type(options) == "table", "invalid options")

  local opts = {
    timer_interval = options and options.timer_interval or TIMER_INTERVAL,
    wait_interval  = options and options.wait_interval  or WAIT_INTERVAL,
    log_interval   = options and options.log_interval   or LOG_INTERVAL,
    threads        = options and options.threads        or THREADS,
    bucket_size    = options and options.bucket_size    or BUCKET_SIZE,
    lawn_size      = options and options.lawn_size      or LAWN_SIZE,
    queue_size     = options and options.query_size     or QUEUE_SIZE,
  }

  local time = new_tab(opts.queue_size, 0)
  for i = 1, opts.queue_size do
    time[i] = new_tab(3, 0)
  end

  return setmetatable({
    opts = opts,
    jobs = new_tab(opts.queue_size, 0),
    time = time,
    work = semaphore.new(),
    lawn = {
      head    = 0,
      tail    = 0,
      ttls    = new_tab(opts.lawn_size, 0),
      buckets = {},
    },
    threads = new_tab(opts.threads, 0),
    buckets = {},
    closest = 0,
    running = 0,
    errored = 0,
    refused = 0,
    aborted = 0,
    done = 0,
    head = 0,
    tail = 0,
  }, async)
end


---
-- Start `resty.async` timers
--
-- @treturn boolean|nil `true` on success, `nil` on error
-- @treturn string|nil  `nil` on success, error message `string` on error
function async:start()
  if exiting() then
    return nil, "nginx worker is exiting"
  end

  if self.started then
    return nil, "already started"
  end

  self.started = now()

  local ok, err = timer_at(0, job_timer, self)
  if not ok then
    return nil, err
  end

  ok, err = timer_every(self.opts.timer_interval, at_timer, self)
  if not ok then
    return nil, err
  end

  ok, err = timer_every(self.opts.log_interval, log_timer, self)
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
  if exiting() then
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
  if exiting() then
    return nil, "nginx worker is exiting"
  end

  delay = DELAYS[delay] or delay

  assert(type(delay) == "number" and delay > 0, "invalid delay, must be a number greater than zero or " ..
                                                "'second', 'minute', 'hour', 'month' or 'year'")

  local bucket = self.buckets[delay]
  local bucket_size = self.opts.bucket_size
  if bucket then
    if bucket.head == bucket_size then
      self.refused = self.refused + 1
      return nil, "async bucket (" .. delay .. ") is full"
    end

  else
    local ok, err = timer_every(delay, every_timer, self, delay)
    if not ok then
      return nil, err
    end

    bucket = {
      jobs = new_tab(bucket_size, 0),
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
  if exiting() then
    return nil, "nginx worker is exiting"
  end

  delay = DELAYS[delay] or delay

  assert(type(delay) == "number" and delay >= 0, "invalid delay, must be a positive number or " ..
                                                 "'second', 'minute', 'hour', 'month' or 'year'")

  if delay == 0 then
    return queue_job(self, false, func, ...)
  end

  local lawn = self.lawn
  local lawn_size = self.opts.lawn_size
  local bucket_size = self.opts.bucket_size
  if get_pending(lawn, lawn_size) == lawn_size then
    self.refused = self.refused + 1
    return nil, "async lawn (" .. delay .. ") is full"
  end

  local bucket = lawn.buckets[delay]
  if bucket then
    if get_pending(bucket, bucket_size) == bucket_size then
      self.refused = self.refused + 1
      return nil, "async bucket (" .. delay .. ") is full"
    end

  else
    lawn.head = lawn.head == lawn_size and 1 or lawn.head + 1
    lawn.ttls[lawn.head] = delay

    bucket = {
      jobs = new_tab(bucket_size, 0),
      head = 0,
      tail = 0,
    }

    lawn.buckets[delay] = bucket
  end

  local expiry = now() + delay

  bucket.head = bucket.head == bucket_size and 1 or bucket.head + 1
  bucket.jobs[bucket.head] = {
    expiry,
    create_at_job(create_job(func, ...)),
  }

  self.closest = min(self.closest, expiry)

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
  local done = min(self.done, self.opts.queue_size)
  if not from and not to then
    return time, done
  end

  from = from and from * 1000 or 0
  to   = to   and to   * 1000 or huge

  local data = new_tab(done, 0)
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
  local pending = get_pending(self, self.opts.queue_size)
  if not opts then
    stats = get_stats(self)
    stats.done    = self.done
    stats.pending = pending
    stats.running = self.running
    stats.errored = self.errored
    stats.refused = self.refused
    stats.aborted = self.aborted

  else
    local current_time = now()

    local all    = opts.all    and get_stats(self)
    local minute = opts.minute and get_stats(self, current_time - DELAYS.minute)
    local hour   = opts.hour   and get_stats(self, current_time - DELAYS.hour)

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
      aborted = self.aborted,
      latency = latency,
      runtime = runtime,
    }
  end

  return stats
end


return async
