-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jit                       = require("jit")
assert(jit.version_num == 20100, "LuaJIT core/library version mismatch")
local profile                   = require("jit.profile")
local resty_lock                = require("resty.lock")
local pl_path                   = require("pl.path")

local math_ceil                 = math.ceil
local debug_getinfo             = debug.getinfo
local string_format             = string.format
local string_sub                = string.sub
local table_insert              = table.insert
local table_concat              = table.concat
local table_remove              = table.remove

local ngx_DEBUG                 = ngx.DEBUG

local ngx_time                  = ngx.time
local ngx_worker_pid            = ngx.worker.pid
local ngx_log                   = ngx.log

local MAX_STACK_DEPTH           = 64  -- depth of stacktrace
local SYNC_INTERVAL             = 1   -- interval of store the
                                      -- current_samples to shdict (in seconds)

local SHDICT_SATATE             = "kong_profiling_state"
local SHDICT_LOCK               = "kong_locks"
local STATE_LOCK_KEY            = "cpu:state_lock"
local FILE_LOCK_KEY             = "cpu:file_lock"
local STATUS_KEY                = "cpu:status"
local PID_KEY                   = "cpu:pid"
local TIMEOUT_AT_KEY            = "cpu:timeout_at"
local STEP_KEY                  = "cpu:step"
local INTERVAL_KEY              = "cpu:count"
local MODE_KEY                  = "cpu:mode"
local PATH_KEY                  = "cpu:path"
local SAMPLES_KEY               = "cpu:samples"

-- For checking the lock status
local LOCK_OPTS_FOR_CHECKING    = { timeout = 0, }
local LOCK_OPTS_FOR_STATE_LOCK  = { timeout = 0, exptime = 0, }
-- For file lock, we assume the time of writing the file is less than 30 seconds
local LOCK_OPTS_FOR_FILE_LOCK   = { timeout = 0, exptime = 30, }

--[[
  The 10 seconds is an arbitrary value,
  we assume it is enough for finishing (such as I/O) the profiling
  after the timeout.
--]]
local TORLERANCE_TIME           = 10

local stacktrace                = {}
local force_stop_at             = math.huge
local current_samples           = 0
local last_sync_samples         = math.huge
local current_state_lock        = nil

local _M                        = {
  VALIDATE_MODES = {
    ["instruction"] = true,
    ["time"] = true,
  },
}


--[[
  There are two types of CPU profiling:
    * instruction-counter-based: It will count the number of
      instructions (byte code) executed by LuaJIT, once the
      counter reaches the limit, it will trigger a callback
      to record the stacktrace.

    * time-based: It will trigger a callback every N microseconds
      to record the stacktrace.

  Why we need two types of CPU profiling?
    * instruction-counter-based: It is more accurate, but it is
      not suitable for some cases, such as a very slow FFI call.
      Beacuse during the FFI call, the LuaJIT VM will not execute
      any byte code, so the counter will not increase, and they
      will not trigger the callback to record the stacktrace.

    * time-based: It is less accurate, but it is suitable some cases
      such as a very slow FFI call.

  The time-based profiler is a buit-in profiler of LuaJIT,
  please see the following link for more details:
  https://github.com/LuaJIT/LuaJIT/blob/4aae8dc2f67158aa3e2a92ca32d8e64f7310d847/doc/ext_profiler.html

  We patched this profiler to support the microseconds interval.
--]]


local function get_shdict()
  return assert(ngx.shared[SHDICT_SATATE])
end


local function sync_samples()
  local shm = get_shdict()
  shm:set(SAMPLES_KEY, current_samples)
end


local function instruction_callback(event, _line)
  if event ~= "count" then
      return
  end

  if ngx_time() > force_stop_at then
      _M.stop()
      return
  end

  local now = ngx_time()

  if now - last_sync_samples > SYNC_INTERVAL then
      last_sync_samples = now
      sync_samples()
  end

  local callstack = {}

  for i = 1, MAX_STACK_DEPTH do
      local info = debug_getinfo(i + 1, "nSl")

      if not info then
          break
      end

      local str = string_format("%s:%d:%s();",
                                info.source,
                                info.currentline,
                                info.name or info.what)

      table_insert(callstack, str)
  end

  -- remove the last ';'
  local top = callstack[1]
  callstack[1] = string_sub(top, 1, -2)

  local _callstack = callstack
  callstack = {}

  -- to adjust the order (reverses the table) of raw data of flamegraph
  for _ = 1, #_callstack do
      table_insert(callstack, table_remove(_callstack))
  end

  local trace = table_concat(callstack, nil)
  stacktrace[trace] = (stacktrace[trace] or 0) + 1

  current_samples = current_samples + 1
end


local function time_callback(th, samples, vmmode)
  if ngx_time() > force_stop_at then
      _M.stop()
      return
  end

  local now = ngx_time()

  if now - last_sync_samples > SYNC_INTERVAL then
      last_sync_samples = now
      sync_samples()
  end

  --[[
    stacktrace = profile.dumpstack([thread,] fmt, depth)

    fmt:
      * "p": Preserve the full path for module names. Otherwise, only the file name is used.
      * "Z": Zap the following characters for the last dumped frame.
      * "l": Dump module:line.
      * ";": add ';' at the end of each frame.
  --]]
  local trace = profile.dumpstack(th, "Zpl;", -MAX_STACK_DEPTH)

  --[[
    samples gives the number of accumulated samples
    since the last callback (usually 1).
  --]]
  current_samples = current_samples + samples

  --[[
    vmmode is a string that can be "J", "G", "C", "I", or "N",

    "J" means JIT compiler
    "G" means garbage collector,
    "C" means C code
    "I" means interpreted code
    "N" means native code
  --]]

  if vmmode == "J" then
      trace = string_format("%sJIT_compiler", trace)
  end

  if vmmode == "G" then
      trace = string_format("%sGC", trace)
  end

  if vmmode == "C" then
      trace = string_format("%sC_code", trace)
  end

  stacktrace[trace] = (stacktrace[trace] or 0) + samples
end


local function mark_active(opt)
  local shm = get_shdict()

  local timeout_at = ngx_time() + opt.timeout
  local step = math_ceil(opt.step)
  local interval = math_ceil(opt.interval)
  local path = opt.path
  local mode = opt.mode

  --[[
      Almostly all keys should be expired after 10 seconds more than the timeout to
      avoid some cases like worker crash, or the worker process is killed by the OS (like OOM).
  --]]
  local expire = opt.timeout + TORLERANCE_TIME

  LOCK_OPTS_FOR_STATE_LOCK.exptime = expire
  current_state_lock = assert(resty_lock:new(SHDICT_LOCK, LOCK_OPTS_FOR_STATE_LOCK))
  assert(current_state_lock:lock(STATE_LOCK_KEY))

  assert(shm:set(STATUS_KEY, "started", expire), "failed to set profiling state")
  assert(shm:set(PID_KEY, ngx_worker_pid(), 0))
  assert(shm:set(TIMEOUT_AT_KEY, timeout_at, expire))
  assert(shm:set(STEP_KEY, step, expire))
  assert(shm:set(INTERVAL_KEY, interval, expire))
  assert(shm:set(MODE_KEY, mode, expire))
  -- path should not be expired, because user needs to know where the file is
  assert(shm:set(PATH_KEY, path, 0))
  assert(shm:set(SAMPLES_KEY, 0, expire))

  force_stop_at = timeout_at
  current_samples = 0
  last_sync_samples = ngx_time()
end


local function mark_inactive()
  local shm = get_shdict()

  assert(shm:set(STATUS_KEY, "stopped", 0), "failed to set profiling state")

  stacktrace = {}
  force_stop_at = math.huge
  last_sync_samples = math.huge

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

  if state.status == "started" then
    state.mode = shm:get(MODE_KEY)
    state.samples = shm:get(SAMPLES_KEY)

    if state.mode == "instruction" then
      state.step = shm:get(STEP_KEY)

    elseif state.mode == "time" then
      state.interval = shm:get(INTERVAL_KEY)

    else
      error("unknown profiling mode: " .. state.mode)
    end

  elseif state.status == "stopped" then
    if state.path and not pl_path.exists(state.path) then
      --[[
        We expect the file is exists if status is "stopped",
        but if the file does not exist,
        we should clear the path because user can't find the file.

        The following reasons may cause this branch:
          * the worker process that is the profiling target is exit before the stop() is called.
          * the worker process that is the profiling target is exit before the timeout is reached.
      --]]
      state.path = nil
    end

  else
    error("unknown profiling status: " .. state.status)
  end

  return state
end


function _M.start(opt)
  if _M.is_active() then
    return nil, "profiling is already in progress"
  end

  mark_active(opt)

  stacktrace = {}

  local step = math_ceil(opt.step)
  local interval = math_ceil(opt.interval)
  local mode = opt.mode

  if mode == "instruction" then
    debug.sethook(instruction_callback, "", step)

  elseif mode == "time" then
    local mask = string_format("i%d", interval)
    profile.start(mask, time_callback)
  end

  return true
end


function _M.stop()
  if not _M.is_active() then
    return
  end

  --[[
    For the CPU profiler,
    the sampling function may be called during the stop() function is running.
    So we need to lock the file to avoid the file is corrupted.
  --]]
  local file_lock = assert(resty_lock:new(SHDICT_LOCK, LOCK_OPTS_FOR_FILE_LOCK))

  local elapsed, _ = file_lock:lock(FILE_LOCK_KEY)

  if not elapsed then
    ngx_log(ngx_DEBUG, "profiler is stopping by another coroutine")
    return
  end

  local state = _M.state()
  local old_stacktrace = stacktrace

  if state.mode == "instruction" then
    debug.sethook()

  else
    profile.stop()
  end

  local fp = assert(io.open(state.path, "w"))

  for k, v in pairs(old_stacktrace) do
    fp:write(string_format("%s %d\n", k, v))
  end

  fp:close()

  mark_inactive()

  assert(file_lock:unlock())
end


return _M
