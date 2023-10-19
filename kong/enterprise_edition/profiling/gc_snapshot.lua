-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local resty_lock                = require "resty.lock"

local ngx_time                  = ngx.time
local ngx_worker_pid            = ngx.worker.pid

local SHDICT_SATATE             = "kong_profiling_state"
local SHDICT_LOCK               = "kong_locks"
local LOCK_KEY                  = "gc-snapshot:lock"
local STATUS_KEY                = "gc-snapshot:status"
local PID_ID_KEY                = "gc-snapshot:pid"
local TIMEOUT_AT_KEY            = "gc-snapshot:timeout_at"
local PATH_KEY                  = "gc-snapshot:path"
local ERROR_KEY                 = "gc-snapshot:error"

-- For checking the lock status
local LOCK_OPTS_FOR_CHECKING    = { timeout = 0 }
local LOCK_OPTS_FOR_LOCK        = { timeout = 0, exptime = 0, }

--[[
  The 10 seconds is an arbitrary value,
  we assume it is enough for finishing (such as I/O) the profiling
  after the timeout.
--]]
local TORLERANCE_TIME           = 10

local current_lock              = nil

local _M                        = {}


local function get_shdict()
  return assert(ngx.shared[SHDICT_SATATE])
end


local function mark_active(path, timeout)
  local shm = get_shdict()

  local timeout_at = ngx_time() + timeout

  --[[
    Almostly all keys should be expired after 10 seconds more than the timeout to
    avoid some cases like worker crash, or the worker process is killed by the OS (like OOM).
  --]]
  local expire = timeout + TORLERANCE_TIME

  LOCK_OPTS_FOR_LOCK.exptime = expire
  current_lock = assert(resty_lock:new(SHDICT_LOCK, LOCK_OPTS_FOR_LOCK))
  assert(current_lock:lock(LOCK_KEY))

  assert(shm:set(STATUS_KEY, "started", expire), "failed to set status")
  assert(shm:set(PID_ID_KEY, ngx_worker_pid(), 0))
  assert(shm:set(TIMEOUT_AT_KEY, timeout_at, expire))
  -- path should not be expired, because user needs to know where the file is
  assert(shm:set(PATH_KEY, path, 0))
  shm:delete(ERROR_KEY)
end


local function mark_inactive()
  local shm = get_shdict()

  assert(shm:set(STATUS_KEY, "stopped", 0), "failed to set status")

  assert(current_lock:unlock())
  current_lock = nil
end


function _M.is_active()
  local lock = assert(resty_lock:new(SHDICT_LOCK, LOCK_OPTS_FOR_CHECKING))

  local elapsed, err = lock:lock(LOCK_KEY)

  if elapsed then
    local ok
    ok, err = lock:unlock()

    if not ok then
      error("failed to unlock: " .. err)
    end

    return false
  end

  if not elapsed and err == "timeout" then
    return true
  end

  error("failed to acquire the lock: " .. err)
end


function _M.state()
  local shm = get_shdict()

  local status = shm:get(STATUS_KEY) or "stopped"
  local pid = shm:get(PID_ID_KEY)
  local timeout_at = shm:get(TIMEOUT_AT_KEY)
  local path = shm:get(PATH_KEY)
  local err = shm:get(ERROR_KEY)

  if status == "stopped" and err == nil then
    return {
      status = "stopped",
      path = path,
      timeout_at = timeout_at,
      pid = pid,
    }
  end

  if status == "stopped" and err ~= nil then
    return {
      status = "error",
      message = err,
    }
  end

  if status == "started" then
    return {
      status = "started",
      pid = pid,
      timeout_at = timeout_at,
      path = path,
    }
  end

  error("unknown status: " .. status)
end


function _M.dump(path, timeout)
  if _M.is_active() then
    return nil, "another gc-snapshot is running"
  end

  mark_active(path, timeout)

  --[[
    ok, err = kprof.mem.gcsnapshot(filename[, timeout=120])

    This function will trigger a full GC cycle, and then dump the Lua VM heap.

    The encoding is messagepack.

    It is a blocking operation, and will block the whole worker.
  
    The timeout is in seconds, and the default value is 120.
    If the timeout is reached, the function will return false and an error message.
    (the timeout is not precise, and the actual time may be longer than the timeout,
    please see the implementation of gcsnapshot() in luajit/src/lj_gcsnapshot.c)
  --]]
  local ok, err = kprof.mem.gcsnapshot(path, timeout) -- luacheck: ignore

  if not ok then
    local shm = get_shdict()
    shm:set(ERROR_KEY, err)
  end

  mark_inactive()
end


return _M
