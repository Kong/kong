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
  }, {
    __call = function(self, lvl, ...) log(lvl, namespace, ...) end,
  })
end
local my_logger = new_logger("[controller]")

-- TODO: might time out
-- @param opts.stdin string the stdin buffer
-- @param opts.logger function(lvl, _, line) stdout+stderr writer; if not defined, whole
-- stdoud and stderr is returned
-- @param opts.stop_signal function return true to abort execution
local function execute(cmd, opts)
  local proc, err = ngx_pipe.spawn(cmd, {
    merge_stderr = true,
  })
  if not proc then
    return false, "failed to start process: " .. err
  end

  if opts and opts.stdin then
    proc:write(opts.stdin)
  end
  proc:shutdown("stdin")

  local log_output = opts and opts.logger
  local ret = {}

  while true do
    local l, err = proc:stdout_read_line()
    if l then
      if log_output then
        opts.logger(ngx.DEBUG, "=> ", l)
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
  "start_upstream", "start_kong", "stop_kong", "setup", "teardown", "start_load", "wait_result",
}

local function check_driver_sanity(mod)
  for _, func in ipairs(driver_functions) do
    if not mod[func] then
      error("Driver " .. debug.getinfo(mod.new, "S").source ..
            " must implement function " .. func, 2)
    end
  end
end

local known_drivers = { "docker" }
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

-- @param opts.tries number retry count
local function invoke_driver(method, opts, ...)
  if not DRIVER then
    error("No driver selected, call use_driver first", 2)
  end
  tries = opts and opts.tries or 3
  local happy
  local r, err
  for i=1, tries do
    r, err = DRIVER[method](DRIVER, ...)
    if not r then
      my_logger.warn("failed in ", method, ": ", err or "nil", ", tries: ", i)
    else
      happy = true
      break
    end
  end
  if not happy then
    error(method .. " finally failed after " .. tries .. " tries", 2)
  end
  return r
end

local _M = {
  use_driver = use_driver,
  new_logger = new_logger,
  set_log_level = set_log_level,
  setenv = setenv,
  unsetenv = unsetenv,
  execute = execute,
}

for _, d in ipairs(driver_functions) do
  _M[d] = function(...)
    local argv = {...}
    -- copy the last table as opts, keep others as it is
    return invoke_driver(d, argv[#argv], ...)
  end
end

return _M