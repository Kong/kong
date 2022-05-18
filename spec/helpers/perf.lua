local pl_tablex = require("pl.tablex")

local logger = require("spec.helpers.perf.logger")
local utils = require("spec.helpers.perf.utils")
local git = require("spec.helpers.perf.git")

local my_logger = logger.new_logger("[controller]")

utils.register_busted_hook()

-- how many times for each "driver" operation
local RETRY_COUNT = 3
local DRIVER
local DRIVER_NAME
local DATA_PLANE

-- Real user facing functions
local driver_functions = {
  "start_upstreams", "start_kong", "stop_kong", "setup", "teardown",
  "get_start_load_cmd", "get_start_stapxx_cmd", "get_wait_stapxx_cmd",
  "generate_flamegraph", "save_error_log",
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
  DRIVER_NAME = name
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
  set_retry_count = set_retry_count,

  new_logger = logger.new_logger,
  set_log_level = logger.set_log_level,

  setenv = utils.setenv,
  unsetenv = utils.unsetenv,
  execute = utils.execute,
  wait_output = utils.wait_output,

  git_checkout = git.git_checkout,
  git_restore = git.git_restore,
  get_kong_version = git.get_kong_version,
}

--- Start the upstream (nginx) with given conf
-- @function start_upstream
-- @param conf string the Nginx nginx snippet under server{} context
-- @return upstream_uri as string
function _M.start_upstream(conf)
  return invoke_driver("start_upstreams", conf, 1)[1]
end

--- Start the upstream (nginx) with given conf with multiple ports
-- @function start_upstream
-- @param conf string the Nginx nginx snippet under server{} context
-- @param port_count number number of ports the upstream listens to
-- @return upstream_uri as string or table if port_count is more than 1
function _M.start_upstreams(conf, port_count)
  return invoke_driver("start_upstreams", conf, port_count)
end

local function dp_conf_from_cp_conf(kong_conf)
  local dp_conf = {}
  for k, v in pairs(kong_conf) do
    dp_conf[k] = v
  end
  dp_conf['role'] = 'data_plane'
  dp_conf['database'] = 'off'
  dp_conf['cluster_control_plane'] = 'kong-cp:8005'
  dp_conf['cluster_telemetry_endpoint'] = 'kong-cp:8006'

  return dp_conf
end

--- Start Kong in hybrid mode with given version and conf
-- @function start_hybrid_kong
-- @param version string Kong version
-- @param kong_confs table Kong configuration as a lua table
-- @return nothing. Throws an error if any.
function _M.start_hybrid_kong(version, kong_confs)
  if DRIVER_NAME ~= 'docker' then
    error("Hybrid support only availabe in Docker driver")
  end
  local kong_confs = kong_confs or {}

  kong_confs['cluster_cert'] = '/kong_clustering.crt'
  kong_confs['cluster_cert_key'] = '/kong_clustering.key'
  kong_confs['role'] = 'control_plane'

  local control_plane = _M.start_kong(version, kong_confs, { container_id = 'cp'})
  local driver_confs = { dns = { ['kong-cp'] = control_plane }, container_id = 'dp' }
  DATA_PLANE = _M.start_kong(version, dp_conf_from_cp_conf(kong_confs), driver_confs)

  if not utils.wait_output("docker logs -f " .. DATA_PLANE, " [DB cache] purging (local) cache") then
    return false, "timeout waiting for DP having it's entities ready (5s)"
  end
end

--- Start Kong with given version and conf
-- @function start_kong
-- @param version string Kong version
-- @param kong_confs table Kong configuration as a lua table
-- @param driver_confs table driver configuration as a lua table
-- @return nothing. Throws an error if any.
function _M.start_kong(version, kong_confs, driver_confs)
  return invoke_driver("start_kong", version, kong_confs or {}, driver_confs or {})
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

  local load_cmd = invoke_driver("get_start_load_cmd", load_cmd_stub, opts.script, opts.uri, DATA_PLANE)
  load_should_stop = false

  load_thread = ngx.thread.spawn(function()
    return utils.execute(load_cmd,
        {
          stop_signal = function() if load_should_stop then return 9 end end,
        })
  end)
end

local stapxx_thread
local stapxx_should_stop

--- Start to send load to Kong
-- @function start_stapxx
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
    return utils.execute(start_cmd,
        {
          stop_signal = function() if stapxx_should_stop then return 3 end end,
        })
  end)

  local wait_cmd = invoke_driver("get_wait_stapxx_cmd")
  if not utils.wait_output(wait_cmd, "stap_", 30) then
    return false, "timeout waiting systemtap probe to load"
  end

  return true
end

--- Wait the load test to finish and get result
-- @function wait_result
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
local nan = 0/0
local function parse_wrk_result(r)
  local rps = string.match(r, "Requests/sec:%s+([%d%.]+)")
  rps = tonumber(rps)
  local count = string.match(r, "([%d]+)%s+requests in")
  count = tonumber(count)
  -- Note: doesn't include case where unit is us: Latency     0.00us    0.00us   0.00us    -nan%
  local lat_avg, avg_m, lat_max, max_m = string.match(r, "Latency%s+([%d%.]+)(m?)s%s+[%d%.]+m?s%s+([%d%.]+)(m?)s")
  lat_avg = tonumber(lat_avg or nan) * (avg_m == "m" and 1 or 1000)
  lat_max = tonumber(lat_max or nan) * (max_m == "m" and 1 or 1000)
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
-- @param title the title for flamegraph
-- @param opts the command line options string(not table) for flamegraph.pl
-- @return Nothing. Throws an error if any.
function _M.generate_flamegraph(filename, title, opts)
  if not filename then
    error("filename must be specified for generate_flamegraph")
  end
  if string.sub(filename, #filename-3, #filename):lower() ~= ".svg" then
    filename = filename .. ".svg"
  end

  if not title then
    title = "Flame graph"
  end

  -- If current test is git-based, also attach the Kong binary package
  -- version it based on
  if git.is_git_repo() and git.is_git_based() then
    title = title .. " (based on " .. git.get_kong_version() .. ")"
  end

  local out = invoke_driver("generate_flamegraph", title, opts)

  local f, err = io.open(filename, "w")
  if not f then
    error("failed to open " .. filename .. " for writing flamegraph: " .. err)
  end

  f:write(out)
  f:close()

  my_logger.debug("flamegraph written to ", filename)
end


--- Save Kong error log locally
-- @function save_error_log
-- @return Nothing. Throws an error if any.
function _M.save_error_log(filename)
  if not filename then
    error("filename must be specified for save_error_log")
  end

  invoke_driver("save_error_log", filename)

  my_logger.debug("Kong error log written to ", filename)
end

return _M
