local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local fmt = string.format

local _M = {}

local dnsmasq_bin_name = "dnsmasq"
local dnsmasq_pid_name = "dnsmasq.pid"
local dnsmasq_search_paths = {
  "/usr/local/sbin",
  "/usr/local/bin",
  "/usr/sbin",
  "/usr/bin",
  "/bin",
  ""
}

function _M.find_bin()
  log.verbose("searching for 'dnsmasq' executable...")

  local found
  for _, path in ipairs(dnsmasq_search_paths) do
    local path_to_check = pl_path.join(path, dnsmasq_bin_name)
    local cmd = fmt("%s -v", path_to_check)
    if pl_utils.executeex(cmd) then
      found = path_to_check
      break
    end
  end

  if not found then
    return nil, "could not find 'dnsmasq' executable"
  end

  log.verbose("found 'dnsmasq' executable at %s", found)

  return found
end

local function is_running(pid_path)
  if not pl_path.exists(pid_path) then return nil end
  local code = kill(pid_path, "-0")
  return code == 0
end

function _M.start(kong_config, nginx_prefix)
  -- is dnsmasq already running in this prefix?
  local pid_path = pl_path.join(nginx_prefix, "pids", dnsmasq_pid_name)
  if is_running(pid_path) then
    log.verbose("dnsmasq already running at %s", pid_path)
    return true
  else
    log.verbose("dnsmasq not running, deleting %s", pid_path)
    pl_file.delete(pid_path)
  end

  local dnsmasq_bin, err = _M.find_bin()
  if not dnsmasq_bin then return nil, err end

  local cmd = fmt("%s -p %d --pid-file=%s -N -o --listen-address=127.0.0.1",
                  dnsmasq_bin, kong_config.dnsmasq_port, pid_path)

  log.debug("starting dnsmasq: %s", cmd)

  local ok, _, _, stderr = pl_utils.executeex(cmd)
  if not ok then return nil, stderr end

  return true
end

function _M.stop(nginx_prefix)
  local pid_path = pl_path.join(nginx_prefix, "pids", dnsmasq_pid_name)
  if pl_path.exists(pid_path) then
    log.verbose("stopping dnsmasq at %s", pid_path)
    return kill(pid_path, "-9")
  end
  return true
end

return _M
