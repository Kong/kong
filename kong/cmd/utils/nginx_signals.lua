local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local fmt = string.format

local nginx_bin_name = "nginx"
local nginx_search_paths = {
  "/usr/local/openresty/nginx/sbin",
  ""
}

local function is_openresty(bin_path)
  local cmd = fmt("%s -v", bin_path)
  local ok, _, _, v_str = pl_utils.executeex(cmd)
  if ok and v_str then
    log.debug("%s: '%s'", cmd, v_str:sub(1, -2))
    return v_str:match "^nginx version: ngx_openresty/" or
           v_str:match "^nginx version: openresty/"
  end
end

local function get_pid_path(nginx_prefix)
  local pid_path = pl_path.join(nginx_prefix, "pids", "nginx.pid")
  if pl_path.exists(pid_path) then
    return pid_path
  end
end

local function send_signal(nginx_prefix, signal)
  local pid_path = get_pid_path(nginx_prefix)
  if not pid_path then
    return nil, "could not get Nginx pid (is Nginx running in this prefix?)"
  end

  log.verbose("sending %s signal to nginx running at %s", signal, pid_path)

  local code = kill(pid_path, "-s "..signal)
  if code ~= 0 then return nil, "could not send signal" end

  return true
end

local _M = {}

function _M.find_bin()
  log.verbose("searching for OpenResty 'nginx' executable...")

  local found
  for _, path in ipairs(nginx_search_paths) do
    local path_to_check = pl_path.join(path, nginx_bin_name)
    local ok = is_openresty(path_to_check)
    if ok then
      found = path_to_check
      break
    end
  end

  if not found then
    return nil, "could not find OpenResty 'nginx' executable"
  end

  log.verbose("found OpenResty 'nginx' executable at %s", found)

  return found
end

function _M.start(nginx_prefix)
  local nginx_bin, err = _M.find_bin()
  if not nginx_bin then return nil, err end

  local pid_path = get_pid_path(nginx_prefix)
  if pid_path then
    local code = kill(pid_path, "-0")
    if code == 0 then
      return nil, "Nginx is already running in "..nginx_prefix
    end
  end

  local cmd = fmt("%s -p %s -c %s", nginx_bin, nginx_prefix, "nginx.conf")

  log.debug("starting nginx: %s", cmd)

  local ok, _, _, stderr = pl_utils.executeex(cmd)
  if not ok then return nil, stderr end

  return true
end

function _M.stop(nginx_prefix)
  return send_signal(nginx_prefix, "QUIT")
end

function _M.reload(nginx_prefix)
  return send_signal(nginx_prefix, "HUP")
end

return _M
