local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
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
    return v_str:match "^nginx version: ngx_openresty/" or
           v_str:match "^nginx version: openresty/"
  end
end

local function get_pid(nginx_prefix)
  local pid_path = pl_path.join(nginx_prefix, "logs", "nginx.pid")
  if pl_path.exists(pid_path) then
    return pl_file.read(pid_path)
  end
end

local function send_signal(nginx_prefix, signal)
  local pid = get_pid(nginx_prefix)
  if not pid then return nil, "could not get Nginx pid (is Kong running?)" end

  local cmd = fmt("kill -s %s %s", signal, pid)

  local ok = pl_utils.execute(cmd)
  if not ok then return nil, "could not send signal" end

  return true
end

local _M = {}

function _M.find_bin()
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

  return found
end

function _M.start(nginx_prefix)
  local nginx_bin, err = _M.find_bin()
  if not nginx_bin then return nil, err end

  local cmd = fmt("%s -p %s -c %s", nginx_bin, nginx_prefix, "nginx.conf")

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
