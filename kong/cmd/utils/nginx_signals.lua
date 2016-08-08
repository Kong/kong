local log = require "kong.cmd.utils.log"
local kill = require "kong.cmd.utils.kill"
local pl_path = require "pl.path"
local version = require "version"
local pl_utils = require "pl.utils"
local fmt = string.format

local nginx_bin_name = "nginx"
local nginx_search_paths = {
  "/usr/local/openresty/nginx/sbin",
  ""
}
local nginx_version_command = "-v"                            -- commandline param to get version
local nginx_version_pattern = "^nginx.-openresty.-([%d%.]+)"  -- pattern to grab version from output
local nginx_compatible = version.set("1.9.15.1")              -- compatible from-to versions

local function is_openresty(bin_path)
  local cmd = fmt("%s %s", bin_path, nginx_version_command)
  local ok, _, _, stderr = pl_utils.executeex(cmd)
  log.debug("%s: '%s'", cmd, stderr:sub(1, -2))
  if ok and stderr then
    local version_match = stderr:match(nginx_version_pattern)
    if not version_match or not nginx_compatible:matches(version_match) then
      log.verbose("incompatible OpenResty found at %s. Kong requires version"..
                  " %s, got %s", bin_path, version_match,
                  tostring(nginx_compatible))
    end
    return true
  end
  log.debug("OpenResty 'nginx' executable not found at %s", bin_path)
end

local function send_signal(pid_path, signal)
  if not pl_path.exists(pid_path) then
    return nil, "could not get Nginx pid (is Nginx running in this prefix?)"
  end

  log.verbose("sending %s signal to Nginx running at %s", signal, pid_path)

  local code = kill.kill(pid_path, "-s "..signal)
  if code ~= 0 then return nil, "could not send signal" end

  return true
end

local _M = {}

local function find_nginx_bin()
  log.verbose("searching for OpenResty 'nginx' executable...")

  local found
  for _, path in ipairs(nginx_search_paths) do
    local path_to_check = pl_path.join(path, nginx_bin_name)
    if is_openresty(path_to_check) then
      found = path_to_check
      log.verbose("found OpenResty 'nginx' executable at %s", found)
      break
    end
  end

  if not found then
    return nil, ("could not find OpenResty 'nginx' executable. Kong requires"..
                 " version %s"):format(tostring(nginx_compatible))
  end

  return found
end

function _M.start(kong_conf)
  local nginx_bin, err = find_nginx_bin()
  if not nginx_bin then return nil, err end

  if kill.is_running(kong_conf.nginx_pid) then
    return nil, "Nginx is already running in "..kong_conf.prefix
  end

  local cmd = fmt("%s -p %s -c %s", nginx_bin, kong_conf.prefix, "nginx.conf")

  log.debug("starting nginx: %s", cmd)

  local ok, _, _, stderr = pl_utils.executeex(cmd)
  if not ok then return nil, stderr end

  return true
end

function _M.stop(kong_conf)
  return send_signal(kong_conf.nginx_pid, "TERM")
end

function _M.quit(kong_conf, graceful)
  return send_signal(kong_conf.nginx_pid, "QUIT")
end

function _M.reload(kong_conf)
  return send_signal(kong_conf.nginx_pid, "HUP")
end

return _M
