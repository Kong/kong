local resty_lock = require "resty.lock"
local ngx_semaphore = require "ngx.semaphore"


local get_phase = ngx.get_phase


local concurrency = {}


-- these must remain for the lifetime of the process
local semaphores = {}


function concurrency.with_worker_mutex(opts, fn)
  if type(opts) ~= "table" then
    error("opts must be a table", 2)
  end
  if type(opts.name) ~= "string" then
    error("opts.name is required and must be a string", 2)
  end
  if opts.timeout and type(opts.timeout) ~= "number" then
    error("opts.timeout must be a number", 2)
  end

  local timeout = opts.timeout or 60

  local rlock, err = resty_lock:new("kong_locks", {
    exptime = timeout,
    timeout = timeout,
  })
  if not rlock then
    return nil, "failed to create worker lock: " .. err
  end

  -- acquire lock
  local elapsed, err = rlock:lock(opts.name)
  if not elapsed then
    if err == "timeout" then
      return nil, err
    end
    return nil, "failed to acquire worker lock: " .. err
  end

  local pok, ok, err = pcall(fn, elapsed)
  if not pok then
    err = ok
    ok = nil
  end

  -- release lock
  rlock:unlock(opts.name)
  return ok, err
end


function concurrency.with_coroutine_mutex(opts, fn)
  if type(opts) ~= "table" then
    error("opts must be a table", 2)
  end
  if type(opts.name) ~= "string" then
    error("opts.name is required and must be a string", 2)
  end
  if opts.timeout and type(opts.timeout) ~= "number" then
    error("opts.timeout must be a number", 2)
  end
  if opts.on_timeout and
     opts.on_timeout ~= "run_unlocked" and
     opts.on_timeout ~= "return_true" then
    error("invalid value for opts.on_timeout", 2)
  end

  if get_phase() == "init_worker" then
    return fn()
  end

  local timeout = opts.timeout or 60

  local semaphore = semaphores[opts.name]

  -- the following `if` block must not yield:
  if not semaphore then
    local err
    semaphore, err = ngx_semaphore.new()
    if err then
      return nil, "failed to create " .. opts.name .. " lock: " .. err
    end
    semaphores[opts.name] = semaphore

    semaphore:post(1)
  end

  -- acquire lock
  local lok, err = semaphore:wait(timeout)
  if not lok then
    if err ~= "timeout" then
      return nil, "error attempting to acquire " .. opts.name .. " lock: " .. err
    end

    if opts.on_timeout == "run_unlocked" then
      kong.log.warn("bypassing ", opts.name, " lock: timeout")
    elseif opts.on_timeout == "return_true" then
      return true
    else
      return nil, "timeout acquiring " .. opts.name .. " lock"
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
