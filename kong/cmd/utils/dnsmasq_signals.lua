local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local fmt = string.format

local _M = {}

local dnsmasq_bin_name = "dnsmasq"
local dnsmasq_search_paths = {
  "/usr/local/sbin",
  "/usr/local/bin",
  "/usr/sbin",
  "/usr/bin",
  "/bin",
  ""
}

local function find_dnsmasq_bin()
  log.debug("searching for 'dnsmasq' executable")

  local found
  for _, path in ipairs(dnsmasq_search_paths) do
    local path_to_check = pl_path.join(path, dnsmasq_bin_name)
    local cmd = fmt("%s -v", path_to_check)
    local ok, _, stdout = pl_utils.executeex(cmd)
    log.debug("%s: '%s'", cmd, pl_stringx.splitlines(stdout)[1])
    if ok then
      found = path_to_check
      break
    end
    log.debug("'dnsmasq' executable not found at %s", path_to_check)
  end

  if not found then
    return nil, "could not find 'dnsmasq' executable"
  end

  log.debug("found 'dnsmasq' executable at %s", found)

  return found
end

function _M.start(kong_config)
  -- is dnsmasq already running in this prefix?
  if kill.is_running(kong_config.dnsmasq_pid) then
    log.verbose("dnsmasq already running at %s", kong_config.dnsmasq_pid)
    return true
  else
    log.verbose("dnsmasq not running, deleting %s", kong_config.dnsmasq_pid)
    pl_file.delete(kong_config.dnsmasq_pid)
  end

  local dnsmasq_bin, err = find_dnsmasq_bin()
  if not dnsmasq_bin then return nil, err end

  local cmd = fmt("%s -p %d --pid-file=%s -N -o --listen-address=127.0.0.1",
                  dnsmasq_bin, kong_config.dnsmasq_port, kong_config.dnsmasq_pid)

  log.debug("starting dnsmasq: %s", cmd)

  local ok, _, _, stderr = pl_utils.executeex(cmd)
  if not ok then return nil, stderr end

  return true
end

function _M.stop(kong_config)
  log.verbose("stopping dnsmasq at %s", kong_config.dnsmasq_pid)
  return kill.kill(kong_config.dnsmasq_pid, "-15") -- SIGTERM
end

return _M
