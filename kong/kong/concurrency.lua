local resty_lock = require "resty.lock"
local ngx_semaphore = require "ngx.semaphore"
local in_yieldable_phase = require("kong.tools.yield").in_yieldable_phase


local type  = type
local error = error
local pcall = pcall


local concurrency = {}


-- these must remain for the lifetime of the process
local semaphores = {}


function concurrency.with_worker_mutex(opts, fn)
  if type(opts) ~= "table" then
    error("opts must be a table", 2)
  end

  local opts_name    = opts.name
  local opts_timeout = opts.timeout
  local opts_exptime = opts.exptime

  if type(opts_name) ~= "string" then
    error("opts.name is required and must be a string", 2)
  end

  if opts_timeout and type(opts_timeout) ~= "number" then
    error("opts.timeout must be a number", 2)
  end

  if opts_exptime and type(opts_exptime) ~= "number" then
    error("opts.exptime must be a number", 2)
  end

  local timeout = opts_timeout or 60
  local exptime = opts_exptime or timeout

  local rlock, err = resty_lock:new("kong_locks", {
    exptime = exptime,
    timeout = timeout,
  })
  if not rlock then
    return nil, "failed to create worker lock: " .. err
  end

  -- acquire lock
  local elapsed, err = rlock:lock(opts_name)
  if not elapsed then
    if err == "timeout" then
      local ttl = rlock.dict and rlock.dict:ttl(opts_name)
      return nil, err, ttl
    end
    return nil, "failed to acquire worker lock: " .. err
  end

  local pok, ok, err = pcall(fn, elapsed)
  if not pok then
    err = ok
    ok = nil
  end

  -- release lock
  rlock:unlock(opts_name)
  return ok, err
end


function concurrency.with_coroutine_mutex(opts, fn)
  if type(opts) ~= "table" then
    error("opts must be a table", 2)
  end

  local opts_name       = opts.name
  local opts_timeout    = opts.timeout
  local opts_on_timeout = opts.on_timeout

  if type(opts_name) ~= "string" then
    error("opts.name is required and must be a string", 2)
  end
  if opts_timeout and type(opts_timeout) ~= "number" then
    error("opts.timeout must be a number", 2)
  end
  if opts_on_timeout and
     opts_on_timeout ~= "run_unlocked" and
     opts_on_timeout ~= "return_true" then
    error("invalid value for opts.on_timeout", 2)
  end

  if not in_yieldable_phase() then
    return fn()
  end

  local timeout = opts_timeout or 60

  local semaphore = semaphores[opts_name]

  -- the following `if` block must not yield:
  if not semaphore then
    local err
    semaphore, err = ngx_semaphore.new()
    if err then
      return nil, "failed to create " .. opts_name .. " lock: " .. err
    end
    semaphores[opts_name] = semaphore

    semaphore:post(1)
  end

  -- acquire lock
  local lok, err = semaphore:wait(timeout)
  if not lok then
    if err ~= "timeout" then
      return nil, "error attempting to acquire " .. opts_name .. " lock: " .. err
    end

    if opts_on_timeout == "run_unlocked" then
      kong.log.warn("bypassing ", opts_name, " lock: timeout")
    elseif opts_on_timeout == "return_true" then
      return true
    else
      return nil, "timeout acquiring " .. opts_name .. " lock"
    end
  end

  local pok, ok, err = pcall(fn)

  if lok then
    -- release lock
    semaphore:post(1)
  end

  if not pok then
    return nil, ok
  end

  return ok, err
end


return concurrency
