-- Enhanced implementation of previous "services.serf.lua" module,
-- no change in actual logic, only decoupled from the events features
-- which now live in kong.serf

local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_file = require "pl.file"
local Serf = require "kong.serf"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local meta = require "kong.meta"
local version = require "version"
local fmt = string.format

local serf_event_name = "kong"
local serf_version_pattern = "^Serf v([%d%.]+)"
local serf_compatible = version.set(unpack(meta._DEPENDENCIES.serf))
local start_timeout = 5
local serf_search_paths = {
  "serf",
  "/usr/local/bin/serf"
}

local function check_version(path)
  local cmd = fmt("%s version", path)
  local ok, _, stdout = pl_utils.executeex(cmd)
  log.debug("%s: '%s'", cmd, pl_stringx.splitlines(stdout)[1])
  if ok and stdout then
    local version_match = stdout:match(serf_version_pattern)
    if not version_match or not serf_compatible:matches(version_match) then
      log.verbose(fmt("incompatible serf found at '%s'. Kong requires version '%s', got '%s'",
                  path, tostring(serf_compatible), version_match))
      return nil
    end
    return true
  end

  log.debug("Serf executable not found at %s", path)
end

local function check_serf_bin(kong_config)
  log.debug("searching for 'serf' executable")

  if kong_config.serf_path then
    serf_search_paths = { kong_config.serf_path }
  end

  local found
  for _, path in ipairs(serf_search_paths) do
    if check_version(path) then
      found = path
      log.debug("found 'serf' executable at %s", found)
      break
    end
  end

  if not found then
    return nil, "could not find 'serf' executable. Kong requires version " ..
                tostring(serf_compatible) ..
                " (you can tweak 'serf_path' to your needs)"
  end

  return found
end

local _M = {}

function _M.start(kong_config, dao)
  -- is Serf already running in this prefix?
  if kill.is_running(kong_config.serf_pid) then
    log.verbose("serf agent already running at %s", kong_config.serf_pid)
    return true
  else
    log.verbose("serf agent not running, deleting %s", kong_config.serf_pid)
    pl_file.delete(kong_config.serf_pid)
  end

  -- make sure Serf is in PATH
  local ok, err = check_serf_bin(kong_config)
  if not ok then return nil, err end

  local serf = Serf.new(kong_config, dao)
  local args = setmetatable({
    ["-bind"] = kong_config.cluster_listen,
    ["-rpc-addr"] = kong_config.cluster_listen_rpc,
    ["-advertise"] = kong_config.cluster_advertise,
    ["-encrypt"] = kong_config.cluster_encrypt_key,
    ["-keyring-file"] = kong_config.cluster_keyring_file,
    ["-log-level"] = "err",
    ["-profile"] = kong_config.cluster_profile,
    ["-node"] = serf.node_name,
    ["-event-handler"] = "member-join,member-leave,member-failed,"
                       .."member-update,member-reap,user:"
                       ..serf_event_name.."="..kong_config.serf_event
  }, Serf.args_mt)

  local cmd = string.format("nohup %s agent %s > %s 2>&1 & echo $! > %s",
                            kong_config.serf_path, tostring(args),
                            kong_config.serf_log, kong_config.serf_pid)

  log.debug("starting serf agent: %s", cmd)

  -- start Serf agent
  local ok = pl_utils.execute(cmd)
  if not ok then return nil end

  log.verbose("waiting for serf agent to be running")

  -- ensure started (just an improved version of previous Serf service)
  local tstart = ngx.time()
  local texp, started = tstart + start_timeout
  repeat
    ngx.sleep(0.2)
    started = kill.is_running(kong_config.serf_pid)
  until started or ngx.time() >= texp

  if not started then
    -- time to get latest error log from serf.log
    local logs = pl_file.read(kong_config.serf_log)
    local tlogs = pl_stringx.split(logs, "\n")
    local err = string.gsub(tlogs[#tlogs-1], "==> ", "")
    err = pl_stringx.strip(err)
    return nil, "could not start serf: "..err
  end

  log.verbose("serf agent started")

  -- cleanup current node from cluster to prevent inconsistency of data
  local ok, err = serf:cleanup()
  if not ok then return nil, err end

  log.verbose("auto-joining serf cluster")
  local ok, err = serf:autojoin()
  if not ok then return nil, err end

  log.verbose("registering serf node in datastore")
  local ok, err = serf:add_node()
  if not ok then return nil, err end

  log.verbose("cluster joined and node registered in datastore")

  return true
end

function _M.stop(kong_config, dao)
  log.verbose("leaving serf cluster")
  local serf = Serf.new(kong_config, dao)
  local ok, err = serf:leave()
  if not ok then return nil, err end
  log.verbose("left serf cluster")

  log.verbose("stopping serf agent at %s", kong_config.serf_pid)
  local code = kill.kill(kong_config.serf_pid, "-15") --SIGTERM
  if code == 256 then -- If no error is returned
    pl_file.delete(kong_config.serf_pid)
  end
  log.verbose("serf agent stopped")
  return true
end

return _M
