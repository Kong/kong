-- Enhanced implementation of previous "services.serf.lua" module,
-- no change in acutal logic, only decoupled from the events features
-- which now live in kong.serf

local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local Serf = require "kong.serf"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"

local serf_bin_name = "serf"
local serf_event_name = "kong"
local start_timeout = 5

local function check_serf_bin()
  local cmd = string.format("%s -v", serf_bin_name)
  local ok, _, stdout = pl_utils.executeex(cmd)
  if ok and stdout then
    if not stdout:match "^Serf v0%.7%.0" then
      return nil, "wrong Serf version (need 0.7.0)"
    end
    return true
  end

  return nil, "could not find Serf executable (is it in your $PATH?)"
end

local function is_running(pid_path)
  if not pl_path.exists(pid_path) then return nil end
  local code = kill(pid_path, "-0")
  return code == 0
end

local _M = {}

function _M.start(kong_config, dao)
  -- is Serf already running in this prefix?
  if is_running(kong_config.serf_pid) then
    log.verbose("Serf agent already running at %s", kong_config.serf_pid)
    return true
  else
    log.verbose("Serf agent not running, deleting %s", kong_config.serf_pid)
    pl_file.delete(kong_config.serf_pid)
  end

  -- make sure Serf is in PATH
  local ok, err = check_serf_bin()
  if not ok then return nil, err end

  local serf = Serf.new(kong_config, dao)
  local args = setmetatable({
    ["-bind"] = kong_config.cluster_listen,
    ["-rpc-addr"] = kong_config.cluster_listen_rpc,
    ["-advertise"] = kong_config.cluster_advertise,
    ["-encrypt"] = kong_config.cluster_encrypt_key,
    ["-log-level"] = "err",
    ["-profile"] = "wan",
    ["-node"] = serf.node_name,
    ["-event-handler"] = "member-join,member-leave,member-failed,"
                       .."member-update,member-reap,user:"
                       ..serf_event_name.."="..kong_config.serf_event
  }, Serf.args_mt)

  local cmd = string.format("nohup %s agent %s > %s 2>&1 & echo $! > %s",
                            serf_bin_name, tostring(args),
                            kong_config.serf_log, kong_config.serf_pid)

  log.debug("starting Serf agent: %s", cmd)

  -- start Serf agent
  local ok = pl_utils.execute(cmd)
  if not ok then return nil end

  -- ensure started (just an improved version of previous Serf service)
  local tstart = ngx.time()
  local texp, started = tstart + start_timeout

  repeat
    log.debug("waiting for Serf agent to be running...")
    ngx.sleep(0.2)
    started = is_running(kong_config.serf_pid)
  until started or ngx.time() >= texp

  if not started then
    -- time to get latest error log from serf.log
    local logs = pl_file.read(kong_config.serf_log)
    local tlogs = pl_stringx.split(logs, "\n")
    local err = string.gsub(tlogs[#tlogs-1], "==> ", "")
    err = pl_stringx.strip(err)
    return nil, "could not start Serf: "..err
  end

  log.verbose("auto-joining Serf cluster...")
  local ok, err = serf:autojoin()
  if not ok then return nil, err end

  log.verbose("adding node to Serf cluster (in datastore)...")
  local ok, err = serf:add_node()
  if not ok then return nil, err end

  return true
end

function _M.stop(kong_config, dao)
  log.info("leaving cluster")

  local serf = Serf.new(kong_config, dao)

  local ok, err = serf:leave()
  if not ok then return nil, err end

  if pl_path.exists(kong_config.serf_pid) then
    log.verbose("stopping Serf agent at %s", kong_config.serf_pid)
    local code = kill(kong_config.serf_pid, "-9")
    pl_file.delete(kong_config.serf_pid)
    return code
  end
  return true
end

return _M
