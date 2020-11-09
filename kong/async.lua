local semaphore = require "ngx.semaphore"


local ngx = ngx
local kong = kong
local pcall = pcall
local select = select
local unpack = unpack
local setmetatable = setmetatable


local QUEUE_SIZE = 100000


local function get_pending(self)
  local head = self.head
  local tail = self.tail
  if head < tail then
    head = head + QUEUE_SIZE
  end
  return head - tail
end


local function job_thread(self, index)
  while not ngx.worker.exiting() do
    local ok, err = self.work:wait(1)
    if ok then
      if self.head ~= self.tail then
        local tail = self.tail == QUEUE_SIZE and 1 or self.tail + 1
        local job = self.jobs[tail]
        self.tail = tail
        self.jobs[tail] = nil
        ok, err = job()
        if not ok then
          kong.log.err("async thread #", index, " job error: ", err)
        end
      end

    elseif err ~= "timeout" then
      kong.log.err("async thread #", index, " wait error: ", err)
    end
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


local async = {}
async.__index = async


---
-- Creates a new instance of `kong.async`
--
-- @treturn table an instance of `kong.async`
function async.new()
  return setmetatable({
    jobs = kong.table.new(QUEUE_SIZE, 0),
    work = semaphore.new(),
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
  local ok, err = ngx.timer.at(0, job_timer, self)
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
  if get_pending(self) == QUEUE_SIZE then
    return nil, "async queue is full"
  end

  self.head = self.head == QUEUE_SIZE and 1 or self.head + 1
  self.jobs[self.head] = create_job(func, ...)
  self.work:post()

  return true
end


return async
