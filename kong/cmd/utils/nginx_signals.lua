local log = require "kong.cmd.utils.log"
local kill = require "kong.cmd.utils.kill"
local meta = require "kong.meta"
local pl_path = require "pl.path"
local version = require "version"
local pl_utils = require "pl.utils"
local pl_stringx = require "pl.stringx"
local fmt = string.format

local nginx_bin_name = "nginx"
local nginx_search_paths = {
  "/usr/local/openresty/nginx/sbin",
  "/opt/openresty/nginx/sbin",
  ""
}
local nginx_version_pattern = "^nginx.-openresty.-([%d%.]+)"
local nginx_compatible = version.set(unpack(meta._DEPENDENCIES.nginx))

local function is_openresty(bin_path)
  local cmd = fmt("%s -v", bin_path)
  local ok, _, _, stderr = pl_utils.executeex(cmd)
  log.debug("%s: '%s'", cmd, stderr:sub(1, -2))
  if ok and stderr then
    local version_match = stderr:match(nginx_version_pattern)
    if not version_match or not nginx_compatible:matches(version_match) then
      log.verbose("incompatible OpenResty found at %s. Kong requires version" ..
                  " %s, got %s", bin_path, tostring(nginx_compatible),
                  version_match)
      return false
    end
    return true
  end
  log.debug("OpenResty 'nginx' executable not found at %s", bin_path)
end

local function send_signal(kong_conf, signal)
  if not kill.is_running(kong_conf.nginx_pid) then
    return nil, "nginx not running in prefix: " .. kong_conf.prefix
  end

  log.verbose("sending %s signal to nginx running at %s", signal, kong_conf.nginx_pid)

  local code = kill.kill(kong_conf.nginx_pid, "-s " .. signal)
  if code ~= 0 then
    return nil, "could not send signal"
  end

  return true
end

local _M = {}

function _M.find_nginx_bin()
  log.debug("searching for OpenResty 'nginx' executable")

  local found
  for _, path in ipairs(nginx_search_paths) do
    local path_to_check = pl_path.join(path, nginx_bin_name)
    if is_openresty(path_to_check) then
      if path_to_check == "nginx" then
        log.debug("finding executable absolute path from $PATH...")
        local ok, code, stdout, stderr = pl_utils.executeex("command -v nginx")
        if ok and code == 0 then
          path_to_check = pl_stringx.strip(stdout)

        else
          log.error("could not find executable absolute path: %s", stderr)
        end
      end

      found = path_to_check
      log.debug("found OpenResty 'nginx' executable at %s", found)
      break
    end
  end

  if not found then
    return nil, ("could not find OpenResty 'nginx' executable. Kong requires" ..
                 " version %s"):format(tostring(nginx_compatible))
  end

  return found
end

function _M.start(kong_conf)
  local nginx_bin, err = _M.find_nginx_bin()
  if not nginx_bin then
    return nil, err
  end

  if kill.is_running(kong_conf.nginx_pid) then
    return nil, "nginx is already running in " .. kong_conf.prefix
  end

  local cmd = fmt("%s -p %s -c %s", nginx_bin, kong_conf.prefix, "nginx.conf")

  log.debug("starting nginx: %s", cmd)

  if kong_conf.nginx_main_daemon == "on" then
    -- running as daemon: capture command output to temp files using the
    -- "executeex" method
    local ok, _, _, stderr = pl_utils.executeex(cmd)
    if not ok then
      return nil, stderr
    end

    log.debug("nginx started")

  else
    -- running in foreground: do not redirect output since long running
    -- processes would produce output filling the disk, use "execute" without
    -- redirection instead.
    local ok, retcode = pl_utils.execute(cmd)
    if not ok then
      return nil, ("failed to start nginx (exit code: %s)"):format(retcode)
    end
  end

  return true
end

function _M.check_conf(kong_conf)
  local nginx_bin, err = _M.find_nginx_bin()
  if not nginx_bin then
    return nil, err
  end

  local cmd = fmt("KONG_NGINX_CONF_CHECK=true %s -t -p %s -c %s",
                  nginx_bin, kong_conf.prefix, "nginx.conf")

  log.debug("testing nginx configuration: %s", cmd)

  local ok, retcode, _, stderr = pl_utils.executeex(cmd)
  if not ok then
    return nil, ("nginx configuration is invalid " ..
                 "(exit code %d):\n%s"):format(retcode, stderr)
  end

  return true
end

function _M.stop(kong_conf)
  return send_signal(kong_conf, "TERM")
end

function _M.quit(kong_conf, graceful)
  return send_signal(kong_conf, "QUIT")
end

function _M.reload(kong_conf)
  if not kill.is_running(kong_conf.nginx_pid) then
    return nil, "nginx not running in prefix: " .. kong_conf.prefix
  end

  local nginx_bin, err = _M.find_nginx_bin()
  if not nginx_bin then
    return nil, err
  end

  local cmd = fmt("%s -p %s -c %s -s %s",
                  nginx_bin, kong_conf.prefix, "nginx.conf", "reload")

  log.debug("reloading nginx: %s", cmd)

  local ok, _, _, stderr = pl_utils.executeex(cmd)
  if not ok then
    return nil, stderr
  end

  return true
end

return _M
