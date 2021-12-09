local ngx_pipe = require("ngx.pipe")
local ffi = require("ffi")

string.startswith = function(s, start) -- luacheck: ignore
  return s and start and start ~= "" and s:sub(1, #start) == start
end

string.endswith = function(s, e) -- luacheck: ignore
  return s and e and e ~= "" and s:sub(#s-#e+1, #s) == e
end

--- Spawns a child process and get its exit code and outputs
-- @param opts.stdin string the stdin buffer
-- @param opts.logger function(lvl, _, line) stdout+stderr writer; if not defined, whole
-- stdout and stderr is returned
-- @param opts.stop_signal function return true to abort execution
-- @return stdout+stderr, err if opts.logger not set; bool+err if opts.logger set
local function execute(cmd, opts)
  -- my_logger.debug("exec: ", cmd)

  local proc, err = ngx_pipe.spawn(cmd, {
    merge_stderr = true,
  })
  if not proc then
    return false, "failed to start process: " .. err
  end

  -- set stdout/stderr read timeout to 1s for faster noticing process exit
  -- proc:set_timeouts(write_timeout?, stdout_read_timeout?, stderr_read_timeout?, wait_timeout?)
  proc:set_timeouts(nil, 1000, 1000, nil)
  if opts and opts.stdin then
    proc:write(opts.stdin)
  end
  proc:shutdown("stdin")

  local log_output = opts and opts.logger
  local ret = {}

  while true do
    -- is it alive?
    local ok = proc:kill(0)
    if not ok then
      break
    end

    local l, err = proc:stdout_read_line()
    if l then
      if log_output then
        log_output(l)
      else
        table.insert(ret, l)
      end
    end
    if err == "closed" then
      break
    end
    local sig = opts and opts.stop_signal and opts.stop_signal()
    if sig then
      proc:kill(sig)
      break
    end
  end
  local ok, msg, code = proc:wait()
  ok = ok and code == 0
  ret = log_output and ok or table.concat(ret, "\n")
  if ok then
    return ret
  else
    return ret, ("process exited with code %d: %s"):format(code, msg)
  end
end

--- Execute a command and return until pattern is found in its output
-- @function wait_output
-- @param cmd string the command the execute
-- @param pattern string the pattern to find in stdout and stderr
-- @param timeout number time in seconds to wait for the pattern
-- @return bool whether the pattern is found
local function wait_output(cmd, pattern, timeout)
  timeout = timeout or 5
  local found
  local co = coroutine.create(function()
    while not found do
      local line = coroutine.yield("yield")
      if line:match(pattern) then
        found = true
      end
    end
  end)

  -- start
  coroutine.resume(co)

  -- don't kill it, it me finish by itself
  ngx.thread.spawn(function()
    execute(cmd, {
      logger = function(line)
        return coroutine.running(co) and coroutine.resume(co, line)
      end,
      stop_signal = function() if found then return 9 end end,
    })
  end)

  ngx.update_time()
  local s = ngx.now()
  while not found and ngx.now() - s <= timeout do
    ngx.update_time()
    ngx.sleep(0.1)
  end

  return found
end

ffi.cdef [[
  int setenv(const char *name, const char *value, int overwrite);
  int unsetenv(const char *name);
]]

--- Set an environment variable
-- @function setenv
-- @param env (string) name of the environment variable
-- @param value the value to set
-- @return true on success, false otherwise
local function setenv(env, value)
  return ffi.C.setenv(env, value, 1) == 0
end


--- Unset an environment variable
-- @function setenv
-- @param env (string) name of the environment variable
-- @return true on success, false otherwise
local function unsetenv(env)
  return ffi.C.unsetenv(env) == 0
end

local handler = require("busted.outputHandlers.base")()
local current_test_element

local function register_busted_hook()
  local busted = require("busted")

  handler.testStart = function(element, parent)
    current_test_element = element
  end

  busted.subscribe({'test', 'start'}, handler.testStart)
end

local function get_test_descriptor(sanitized)
  if current_test_element then
    local msg = handler.getFullName(current_test_element)
    local common_prefix = "perf test for Kong "
    if msg:startswith(common_prefix) then
      msg = msg:sub(#common_prefix+1)
    end
    if sanitized then
      msg = msg:gsub("[:/]", "#"):gsub("[ ,]", "_"):gsub("__", "_")
    end
    return msg
  end
end

local function get_test_output_filename()
  return get_test_descriptor(true)
end

return {
  execute = execute,
  wait_output = wait_output,
  setenv = setenv,
  unsetenv = unsetenv,
  register_busted_hook = register_busted_hook,
  get_test_descriptor = get_test_descriptor,
  get_test_output_filename = get_test_output_filename,
}
