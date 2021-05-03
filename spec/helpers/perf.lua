local pl_tablex = require("pl.tablex")
local ngx_pipe = require("ngx.pipe")
local tty = require("kong.cmd.utils.tty")
local ffi = require("ffi")

local colors

if not tty.isatty then
  colors = setmetatable({}, {__index = function() return "" end})
else
  colors = { green = '\27[32m', yellow = '\27[33m', red = '\27[31m', reset = '\27[0m' }
end

local LOG_LEVEL = ngx.NOTICE
-- how many times for each "driver" operation
local RETRY_COUNT = 3
local DRIVER

-- Some logging helpers
local level_cfg = {
  [ngx.DEBUG] = { "debug", colors.green },
  [ngx.INFO] = { "info", "" },
  [ngx.NOTICE] = { "notice", "" },
  [ngx.WARN] = { "warn",  colors.yellow },
  [ngx.ERR] = { "error", colors.red },
  [ngx.CRIT] = { "crit", colors.red },
}

local function set_log_level(lvl)
  if not level_cfg[lvl] then
    error("Unknown log level ", lvl, 2)
  end
  LOG_LEVEL = lvl
end

local function log(lvl, namespace, ...)
  lvl = lvl or ngx.INFO
  local lvl_literal, lvl_color = unpack(level_cfg[lvl] or {"info", ""})
  if lvl <= LOG_LEVEL then
    ngx.update_time()
    local msec = ngx.now()
    print(lvl_color,
          ("%s%s [%s] %s "):format(
            ngx.localtime():sub(12),
            ("%.3f"):format(msec - math.floor(msec)):sub(2),
            lvl_literal, namespace
          ),
          table.concat({...}, ""),
          colors.reset)
  end
end
local function new_logger(namespace)
  return setmetatable({
    debug = function(...) log(ngx.DEBUG, namespace, ...) end,
    info = function(...) log(ngx.INFO, namespace, ...) end,
    warn = function(...) log(ngx.WARN, namespace, ...) end,
    err = function(...) log(ngx.ERR, namespace, ...) end,
    crit = function(...) log(ngx.CRIT, namespace, ...) end,
    log_exec = function(...) log(ngx.DEBUG, namespace, "=> ", ...) end,
  }, {
    __call = function(self, lvl, ...) log(lvl, namespace, ...) end,
  })
end
local my_logger = new_logger("[controller]")

string.startswith = function(s, start) -- luacheck: ignore
  return s and start and start ~= "" and s:sub(1, #start) == start
end

string.endswith = function(s, e) -- luacheck: ignore
  return s and e and e ~= "" and s:sub(#s-#e+1, #s) == e
end

--- Spawns a child process and get its exit code and outputs
-- @param opts.stdin string the stdin buffer
-- @param opts.logger function(lvl, _, line) stdout+stderr writer; if not defined, whole
-- stdoud and stderr is returned
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
        opts.logger(l)
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

-- Real user facing functions
local driver_functions = {
  "start_upstream", "start_kong", "stop_kong", "setup", "teardown",
  "get_start_load_cmd", "get_start_stapxx_cmd", "get_wait_stapxx_cmd",
  "generate_flamegraph",
}

local function check_driver_sanity(mod)
  if type(mod) ~= "table" then
    error("Driver must return a table")
  end

  for _, func in ipairs(driver_functions) do
    if not mod[func] then
      error("Driver " .. debug.getinfo(mod.new, "S").source ..
            " must implement function " .. func, 2)
    end
  end
end

local known_drivers = { "docker", "local", "terraform" }
--- Unset an environment variable
-- @function use_driver
-- @param name string name of the driver to use
-- @param opts[optional] table config parameters passed to the driver
-- @return nothing. Throws an error if any.
local function use_driver(name, opts)
  name = name or "docker"

  if not pl_tablex.find(known_drivers, name) then
    local err = ("Unknown perf test driver \"%s\", expect one of \"%s\""):format(
      name, table.concat(known_drivers, "\", \"")
    )
    error(err, 2)
  end

  local pok, mod = pcall(require, "spec.helpers.perf.drivers." .. name)

  if not pok then
    error(("Unable to load perf test driver %s: %s"):format(name, mod))
  end

  check_driver_sanity(mod)
  
  DRIVER = mod.new(opts)
end

--- Set driver operation retry count
-- @function set_retry_count
-- @param try number the retry time for each driver operation
-- @return nothing.
local function set_retry_count(try)
  if type(try) ~= "number" then
    error("expect a number, got " .. type(try))
  end
  RETRY_COUNT = try
end

local function invoke_driver(method, ...)
  if not DRIVER then
    error("No driver selected, call use_driver first", 2)
  end
  local happy
  local r, err
  for i=1, RETRY_COUNT do
    r, err = DRIVER[method](DRIVER, ...)
    if not r then
      my_logger.warn("failed in ", method, ": ", err or "nil", ", tries: ", i)
    else
      happy = true
      break
    end
  end
  if not happy then
    error(method .. " finally failed after " .. RETRY_COUNT .. " tries", 2)
  end
  return r
end

local _M = {
  use_driver = use_driver,
  new_logger = new_logger,
  set_log_level = set_log_level,
  setenv = setenv,
  unsetenv = unsetenv,
  set_retry_count = set_retry_count,
  execute = execute,
  wait_output = wait_output,
}

--- Start the upstream (nginx) with given conf
-- @function start_upstream
-- @param conf string the Nginx nginx snippet under server{} context
-- @return nothing. Throws an error if any.
function _M.start_upstream(conf)
  return invoke_driver("start_upstream", conf)
end

--- Start Kong with given version and conf
-- @function start_kong
-- @param version string Kong version
-- @param kong_confs table Kong configuration as a lua table
-- @return nothing. Throws an error if any.
function _M.start_kong(version, kong_confs)
  return invoke_driver("start_kong", version, kong_confs)
end

--- Stop Kong
-- @function stop_kong
-- @return nothing. Throws an error if any.
function _M.stop_kong()
  return invoke_driver("stop_kong")
end

--- Setup env vars and return the configured helpers utility
-- @function setup
-- @return table the `helpers` utility as if it's require("spec.helpers")
function _M.setup()
  return invoke_driver("setup")
end

--- Cleanup all the stuff
-- @function teardown
-- @param full[optional] boolean teardown all stuff, including those will
-- make next test spin up faster
-- @return nothing. Throws an error if any.
function _M.teardown(full)
  return invoke_driver("teardown", full)
end

local load_thread
local load_should_stop

--- Start to send load to Kong
-- @function start_load
-- @param opts.path[optional] string request path, default to /
-- @param opts.uri[optional] string base URI except path, default to http://kong-ip:kong-port/
-- @param opts.connections[optional] number connection count, default to 1000
-- @param opts.threads[optional] number request thread count, default to 5
-- @param opts.duration[optional] number perf test duration in seconds, default to 10
-- @param opts.script[optional] string content of wrk script, default to nil
-- @return nothing. Throws an error if any.
function _M.start_load(opts)
  if load_thread then
    error("load is already started, stop it using wait_result() first", 2)
  end

  local path = opts.path or ""
  -- strip leading /
  if path:sub(1, 1) == "/" then
    path = path:sub(2)
  end

  local load_cmd_stub = "wrk -c " .. (opts.connections or 1000) ..
                        " -t " .. (opts.threads or 5) ..
                        " -d " .. (opts.duration or 10) ..
                        " %s " .. -- script place holder
                        " %s/" .. path

  local load_cmd = invoke_driver("get_start_load_cmd", load_cmd_stub, opts.script, opts.uri)
  load_should_stop = false

  load_thread = ngx.thread.spawn(function()
    return execute(load_cmd,
        {
          stop_signal = function() if load_should_stop then return 9 end end,
        })
  end)
end

local stapxx_thread
local stapxx_should_stop

--- Start to send load to Kong
-- @function start_load
-- @param sample_name string stapxx sample name
-- @param ... string extra arguments passed to stapxx script
-- @return nothing. Throws an error if any.
function _M.start_stapxx(sample_name, ...)
  if stapxx_thread then
    error("stapxx is already started, stop it using wait_result() first", 2)
  end

  local start_cmd = invoke_driver("get_start_stapxx_cmd", sample_name, ...)
  stapxx_should_stop = false

  stapxx_thread = ngx.thread.spawn(function()
    return execute(start_cmd,
        {
          stop_signal = function() if stapxx_should_stop then return 3 end end,
        })
  end)

  local wait_cmd = invoke_driver("get_wait_stapxx_cmd")
  if not wait_output(wait_cmd, "stap_", 30) then
    return false, "timeout waiting systemtap probe to load"
  end

  return true
end

--- Wait the load test to finish and get result
-- @function start_load
-- @param opts.path string request path
-- @return string the test report text
function _M.wait_result(opts)
  if not load_thread then
    error("load haven't been started or already collected, " .. 
          "start it using start_load() first", 2)
  end

  -- local timeout = opts and opts.timeout or 3
  -- local ok, res, err

  -- ngx.update_time()
  -- local s = ngx.now()
  -- while not found and ngx.now() - s <= timeout do
  --   ngx.update_time()
  --   ngx.sleep(0.1)
  --   if coroutine.status(self.load_thread) ~= "running" then
  --     break
  --   end
  -- end
  -- print(coroutine.status(self.load_thread), coroutine.running(self.load_thread))

  -- if coroutine.status(self.load_thread) == "running" then
  --   self.load_should_stop = true
  --   return false, "timeout waiting for load to stop (" .. timeout .. "s)"
  -- end

  if stapxx_thread then
    local ok, res, err = ngx.thread.wait(stapxx_thread)
    stapxx_should_stop = true
    stapxx_thread = nil
    if not ok or err then
      my_logger.warn("failed to wait stapxx to finish: ",
        (res or "nil"),
        " err: " .. (err or "nil"))
    end
    my_logger.debug("stap++ output: ", res)
  end

  local ok, res, err = ngx.thread.wait(load_thread)
  load_should_stop = true
  load_thread = nil

  if not ok or err then
    error("failed to wait result: " .. (res or "nil") ..
          " err: " .. (err or "nil"))
  end

  return res
end

local function sum(t)
  local s = 0
  for _, i in ipairs(t) do
    if type(i) == "number" then
      s = s + i
    end
  end

  return s
end

-- Note: could also use custom lua code in wrk
local function parse_wrk_result(r)
  local rps = string.match(r, "Requests/sec:%s+([%d%.]+)")
  rps = tonumber(rps)
  local count = string.match(r, "([%d]+)%s+requests in")
  count = tonumber(count)
  local lat_avg, avg_m, lat_max, max_m = string.match(r, "Latency%s+([%d%.]+)(m?)s%s+[%d%.]+m?s%s+([%d%.]+)(m?)s")
  lat_avg = tonumber(lat_avg) * (avg_m == "m" and 1 or 1000)
  lat_max = tonumber(lat_max) * (max_m == "m" and 1 or 1000)
  return rps, count, lat_avg, lat_max
end

--- Compute average of RPS and latency from multiple wrk output
-- @results table the table holds raw wrk outputs
-- @return string. The human readable result of average RPS and latency
function _M.combine_results(results)
  local count = #results
  if count == 0 then
    return "(no results)"
  end

  local rpss = table.new(count, 0)
  local latencies_avg = table.new(count, 0)
  local latencies_max = table.new(count, 0)
  local count = 0

  for i, result in ipairs(results) do
    local r, c, la, lm = parse_wrk_result(result)
    rpss[i] = r
    count = count + c
    latencies_avg[i] = la * c
    latencies_max[i] = lm
  end

  local rps = sum(rpss) / 3
  local latency_avg = sum(latencies_avg) / count
  local latency_max = math.max(unpack(latencies_max))

  return ([[
RPS     Avg: %3.2f
Latency Avg: %3.2fms    Max: %3.2fms
  ]]):format(rps, latency_avg, latency_max)
end

--- Wait until the systemtap probe is loaded
-- @function wait_stap_probe
function _M.wait_stap_probe(timeout)
  return invoke_driver("wait_stap_probe", timeout or 20)
end

--- Generate the flamegraph and return SVG
-- @function generate_flamegraph
-- @return string. The SVG image as string.
function _M.generate_flamegraph(filename)
  if not filename then
    error("filename must be specified for generate_flamegraph")
  end
  if string.sub(filename, #filename-3, #filename):lower() ~= ".svg" then
    filename = filename .. ".svg"
  end

  local out = invoke_driver("generate_flamegraph")

  local f, err = io.open(filename, "w")
  if not f then
    error("failed to open " .. filename .. " for writing flamegraph: " .. err)
  end

  f:write(out)
  f:close()

  my_logger.debug("flamegraph written to ", filename)
end


local git_stashed, git_head
function _M.git_checkout(version)
  if not execute("which git") then
    error("git binary not found")
  end

  local res, err
  local hash, _ = execute("git rev-parse HEAD")
  if not hash or not hash:match("[a-f0-f]+") then
    error("Unable to parse HEAD pointer, is this a git repository?")
  else
    -- am i on a named branch/tag?
    local n, _ = execute("git rev-parse --abbrev-ref HEAD")
    if n then
      hash = n
    end
    -- anything to save?
    n, err = execute("git status --untracked-files=no --porcelain")
    if not err and (n and #n > 0) then
      my_logger.info("saving your working directory")
      res, err = execute("git stash save kong-perf-test-autosaved")
      if err then
        error("Cannot save your working directory: " .. err .. (res or "nil"))
      end
      git_stashed = true
    end

    my_logger.debug("switching away from ", hash, " to ", version)

    res, err = execute("git checkout " .. version)
    if err then
      error("Cannot switch to " .. version .. ":\n" .. res)
    end
    if not git_head then
      git_head = hash
    end
  end
end

function _M.git_restore()
  if git_head then
    local res, err = execute("git checkout " .. git_head)
    if err then
      return false, "git checkout: " .. res
    end
    git_head = nil

    if git_stashed then
      local res, err = execute("git stash pop")
      if err then
        return false, "git stash pop: " .. res
      end
      git_stashed = false
    end
  end
end

function _M.get_kong_version()
  local ok, meta, _ = pcall(require, "kong.meta")
  if ok then
    return meta._VERSION
  end
  error("can't read Kong version from kong.meta: " .. (meta or "nil"))
end

return _M