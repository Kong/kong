local ngx_pipe = require("ngx.pipe")
local ffi = require("ffi")
local cjson_safe = require("cjson.safe")
local logger = require("spec.helpers.perf.logger")
local log = logger.new_logger("[controller]")

local DISABLE_EXEC_OUTPUT = os.getenv("PERF_TEST_DISABLE_EXEC_OUTPUT") or false

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
-- @return stdout+stderr string, err|nil
local function execute(cmd, opts)
  local log_output = opts and opts.logger

  -- skip if PERF_TEST_DISABLE_EXEC_OUTPUT is set
  if not DISABLE_EXEC_OUTPUT then
    -- fallback to default logger if not defined
    log_output = log_output or log.debug
    log_output("[exec]: ", cmd)
  end

  local proc, err = ngx_pipe.spawn(cmd, {
    merge_stderr = true,
  })
  if not proc then
    return "", "failed to start process: " .. err
  end

  -- set stdout/stderr read timeout to 1s for faster noticing process exit
  -- proc:set_timeouts(write_timeout?, stdout_read_timeout?, stderr_read_timeout?, wait_timeout?)
  proc:set_timeouts(nil, 1000, 1000, nil)
  if opts and opts.stdin then
    proc:write(opts.stdin)
  end
  proc:shutdown("stdin")

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
      end

      -- always store output
      table.insert(ret, l)
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
  ret = table.concat(ret, "\n")
  if ok then
    return ret
  end

  return ret, ("process exited with code %s: %s"):format(code, msg)
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

local function get_test_descriptor(sanitized, element_override)
  local elem = current_test_element or element_override
  if elem then
    local msg = handler.getFullName(elem)
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

local function parse_docker_image_labels(docker_inspect_output)
  local m, err = cjson_safe.decode(docker_inspect_output)
  if err then
    return nil, err
  end

  local labels = m[1].Config.Labels or {}
  labels.version = labels["org.opencontainers.image.version"] or "unknown_version"
  labels.revision = labels["org.opencontainers.image.revision"] or "unknown_revision"
  labels.created = labels["org.opencontainers.image.created"] or "unknown_created"
  return labels
end

local original_lua_package_paths = package.path
local function add_lua_package_paths(d)
  d = d or "."
  local pp = d .. "/?.lua;" ..
       d .. "/?/init.lua;"
  local pl_dir = require("pl.dir")
  local pl_path = require("pl.path")
  if pl_path.isdir(d .. "/plugins-ee") then
    for _, p in ipairs(pl_dir.getdirectories(d .. "/plugins-ee")) do
      pp = pp.. p .. "/?.lua;"..
                p .. "/?/init.lua;"
    end
  end
  package.path = pp .. ";" .. original_lua_package_paths
end

local function restore_lua_package_paths()
  package.path = original_lua_package_paths
end

-- clear certain packages to allow spec.helpers to be re-imported
-- those modules are only needed to run migrations in the "controller"
-- and won't affect kong instances performing tests
local function clear_loaded_package()
  for _, p in ipairs({
    "spec.helpers", "kong.cluster_events",
    "kong.global", "kong.constants",
    "kong.cache", "kong.db", "kong.plugins", "kong.pdk", "kong.enterprise_edition.pdk",
  }) do
    package.loaded[p] = nil
  end
end

local function print_and_save(s, path)
  local shell = require "resty.shell"
  shell.run("mkdir -p output", nil, 0)
  print(s)
  local f = io.open(path or "output/result.txt", "a")
  f:write(s)
  f:write("\n")
  f:close()
end

return {
  execute = execute,
  wait_output = wait_output,
  setenv = setenv,
  unsetenv = unsetenv,
  register_busted_hook = register_busted_hook,
  get_test_descriptor = get_test_descriptor,
  get_test_output_filename = get_test_output_filename,
  parse_docker_image_labels = parse_docker_image_labels,
  add_lua_package_paths = add_lua_package_paths,
  restore_lua_package_paths = restore_lua_package_paths,
  clear_loaded_package = clear_loaded_package,
  print_and_save = print_and_save,
}
