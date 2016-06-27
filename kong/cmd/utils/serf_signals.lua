-- Enhanced implementation of previous "services.serf.lua" module,
-- no change in acutal logic, only decoupled from the events features
-- which now live in kong.serf

local Serf = require "kong.serf"

local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local utils = require "kong.tools.utils"
local fmt = string.format

local serf_bin_name = "serf"
local serf_pid_name = "serf.pid"
local serf_node_id = "serf.id"
local serf_event_name = "kong"
local start_timeout = 5

local function check_serf_bin()
  local cmd = fmt("%s -v", serf_bin_name)
  local ok, _, stdout = pl_utils.executeex(cmd)
  if ok and stdout then
    if not stdout:match "^Serf v0%.7%.0" then
      return nil, "wrong Serf version (need 0.7.0)"
    end
    return true
  end

  return nil, "could not find Serf executable (is it in your $PATH?)"
end

-- script from old services.serf module
local script_template = [[
#!/bin/sh

PAYLOAD=`cat` # Read from stdin
if [ "$SERF_EVENT" != "user" ]; then
  PAYLOAD="{\"type\":\"${SERF_EVENT}\",\"entity\": \"${PAYLOAD}\"}"
fi

CMD="\
local http = require 'resty.http' \
local client = http.new() \
client:connect('%s', %d) \
client:request { \
  method = 'POST', \
  path = '/cluster/events/', \
  body = [=[${PAYLOAD}]=], \
  headers = { \
    ['content-type'] = 'application/json' \
  } \
}"

resty -e "$CMD"
]]

local function prepare_identifier(kong_config, nginx_prefix)
  local serf_path = pl_path.join(nginx_prefix, "serf")
  local ok, err = pl_dir.makepath(serf_path)
  if not ok then return nil, err end

  local id_path = pl_path.join(nginx_prefix, "serf", serf_node_id)
  if not pl_path.exists(id_path) then
    local id = utils.get_hostname().."_"..kong_config.cluster_listen.."_"..utils.random_string()

    log.verbose("saving Serf identifier in %s", id_path)
    local ok, err = pl_file.write(id_path, id)
    if not ok then return nil, err end
  end
  return true
end

local function prepare_prefix(kong_config, nginx_prefix, script_path)
  local ok, err = prepare_identifier(kong_config, nginx_prefix)
  if not ok then return nil, err end

  log.verbose("dumping Serf shell script handler in %s", script_path)
  local script = fmt(script_template, "127.0.0.1", kong_config.admin_port)

  local ok, err = pl_file.write(script_path, script)
  if not ok then return nil, err end
  local ok, _, _, stderr = pl_utils.executeex("chmod +x "..script_path)
  if not ok then return nil, stderr end

  return true
end

local function is_running(pid_path)
  if not pl_path.exists(pid_path) then return nil end
  local code = kill(pid_path, "-0")
  return code == 0
end

local _M = {}

function _M.start(kong_config, nginx_prefix, dao)
  -- is Serf already running in this prefix?
  local pid_path = pl_path.join(nginx_prefix, "pids", serf_pid_name)
  if is_running(pid_path) then
    log.verbose("Serf agent already running at %s", pid_path)
    return true
  else
    log.verbose("Serf agent not running, deleting %s", pid_path)
    pl_file.delete(pid_path)
  end

  -- prepare shell script
  local script_path = pl_path.join(nginx_prefix, "serf", "serf_event.sh")
  local ok, err = prepare_prefix(kong_config, nginx_prefix, script_path)
  if not ok then return nil, err end

  -- make sure Serf is in PATH
  local ok, err = check_serf_bin()
  if not ok then return nil, err end

  local serf = Serf.new(kong_config, nginx_prefix, dao)

  local node_name = serf.node_name
  local log_path = pl_path.join(nginx_prefix, "logs", "serf.log")

  local args = setmetatable({
    ["-bind"] = kong_config.cluster_listen,
    ["-rpc-addr"] = kong_config.cluster_listen_rpc,
    ["-advertise"] = kong_config.cluster_advertise,
    ["-encrypt"] = kong_config.cluster_encrypt_key,
    ["-log-level"] = "err",
    ["-profile"] = "wan",
    ["-node"] = node_name,
    ["-event-handler"] = "member-join,member-leave,member-failed,"
                       .."member-update,member-reap,user:"
                       ..serf_event_name.."="..script_path
  }, Serf.args_mt)

  local cmd = fmt("nohup %s agent %s > %s 2>&1 & echo $! > %s",
                  serf_bin_name, tostring(args),
                  log_path, pid_path)

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
    started = is_running(pid_path)
  until started or ngx.time() >= texp

  if not started then
    -- time to get latest error log from serf.log
    local logs = pl_file.read(log_path)
    local tlogs = pl_stringx.split(logs, "\n")
    local err = string.gsub(tlogs[#tlogs-1], "==> ", "")
    err = pl_stringx.strip(err)
    return nil, "could not start Serf:\n  "..err
  end

  log.verbose("auto-joining Serf cluster...")
  local ok, err = serf:autojoin()
  if not ok then return nil, err end

  log.verbose("adding node to Serf cluster (in datastore)...")
  local ok, err = serf:add_node()
  if not ok then return nil, err end

  return true
end

function _M.stop(kong_config, nginx_prefix, dao)
  log.info("Leaving cluster")

  local serf = Serf.new(kong_config, nginx_prefix, dao)

  local ok, err = serf:leave()
  if not ok then return nil, err end

  local pid_path = pl_path.join(nginx_prefix, "pids", serf_pid_name)
  log.verbose("stopping Serf agent at %s", pid_path)
  local code = kill(pid_path, "-9")
  pl_file.delete(pid_path)
  return code
end

return _M
