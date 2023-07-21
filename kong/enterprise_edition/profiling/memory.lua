-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local resty_lock                = require("resty.lock")

local ngx_time                  = ngx.time
local ngx_worker_pid            = ngx.worker.pid

local SHDICT_SATATE             = "kong_profiling_state"
local SHDICT_LOCK               = "kong_locks"
local STATE_LOCK_KEY            = "memory:state_lock"
local STATUS_KEY                = "memory:status"
local PID_KEY                   = "memory:pid"
local TIMEOUT_AT_KEY            = "memory:timeout_at"
local PATH_KEY                  = "memory:path"
local BLOCK_SIZE_KEY            = "memory:block_size"
local STACK_DEPTH_KEY           = "memory:stack_depth"
local ERROR_KEY                 = "memory:error"


-- For checking the lock status
local LOCK_OPTS_FOR_CHECKING    = { timeout = 0, }
local LOCK_OPTS_FOR_STATE_LOCK  = { timeout = 0, exptime = 0, }

local current_state_lock        = nil

local _M                        = {}


local function get_shdict()
  return assert(ngx.shared[SHDICT_SATATE])
end


local function mark_active(opt)
  local shm = get_shdict()

  local timeout_at = ngx_time() + opt.timeout
  local path = opt.path

  --[[
      Almostly all keys should be expired after timeout
  --]]
  local expire = opt.timeout

  LOCK_OPTS_FOR_STATE_LOCK.exptime = expire
  current_state_lock = assert(resty_lock:new(SHDICT_LOCK, LOCK_OPTS_FOR_STATE_LOCK))
  assert(current_state_lock:lock(STATE_LOCK_KEY))

  assert(shm:set(STATUS_KEY, "started", expire), "failed to set profiling state")
  assert(shm:set(PID_KEY, ngx_worker_pid(), expire))
  assert(shm:set(TIMEOUT_AT_KEY, timeout_at, expire))
  assert(shm:set(BLOCK_SIZE_KEY, opt.block_size, expire))
  assert(shm:set(STACK_DEPTH_KEY, opt.stack_depth, expire))
  -- path should not be expired, because user needs to know where the file is
  assert(shm:set(PATH_KEY, path, 0))
  shm:delete(ERROR_KEY)
end


local function mark_inactive()
  local shm = get_shdict()

  assert(shm:set(STATUS_KEY, "stopped", 0), "failed to set profiling state")

  assert(current_state_lock:unlock())
  current_state_lock = nil
end


function _M.is_active()
  local lock = assert(resty_lock:new(SHDICT_LOCK, LOCK_OPTS_FOR_CHECKING))

  local elapsed, err = lock:lock(STATE_LOCK_KEY)

  if elapsed then
    assert(lock:unlock())
    return false
  end

  if not elapsed and err == "timeout" then
    return true
  end

  error("failed to acquire the lock: " .. err)
end


function _M.state()
  local state = {}
  local shm = get_shdict()

  state.status = shm:get(STATUS_KEY) or "stopped"
  state.path = shm:get(PATH_KEY)
  state.pid = shm:get(PID_KEY)
  state.timeout_at = shm:get(TIMEOUT_AT_KEY)
  state.block_size = shm:get(BLOCK_SIZE_KEY)
  state.stack_depth = shm:get(STACK_DEPTH_KEY)

  if state.status == "started" then
    state.error = (kprof.mem.status()).error
    shm:set(ERROR_KEY, state.error)

  else
    if not state.error then
      state.error = shm:get(ERROR_KEY)
    end

    if state.error then
      state.status = "error"
    end
  end

  return state
end


function _M.start(opt)
  if _M.is_active() then
    return nil, "memory tracing is already in progress"
  end

  assert(opt.path, "path is required")
  assert(opt.block_size, "size is required")
  assert(opt.stack_depth, "stack_depth is required")
  assert(opt.timeout, "timeout is required")

  mark_active(opt)

  --[[
    ok, err = kprof.mem.start(path, block_size, stack_depth[, timeout = 120])

    This function will start the memory tracing to collect the following information:
      - memory allocation
      - memory free
      - memory reallocation
      - stack traceback

    The memory tracing will be stopped automatically after the timeout (in seconds).
  --]]
  local ok, err = kprof.mem.start(opt.path, opt.block_size, opt.stack_depth, opt.timeout)

  if not ok then
    local shm = get_shdict()
    shm:set(ERROR_KEY, err)
    mark_inactive()
    return nil, err
  end

  return true
end


function _M.stop()
  -- PLEASE DONT YIELD IN THIS FUNCTION
  if not _M.is_active() then
    return
  end

  local ok, err = kprof.mem.stop()
  if not ok then
    local shm = get_shdict()
    shm:set(ERROR_KEY, err)
  end

  mark_inactive()
end


return _M
