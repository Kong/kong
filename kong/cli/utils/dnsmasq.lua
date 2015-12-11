local IO = require "kong.tools.io"
local cutils = require "kong.cli.utils"
local constants = require "kong.constants"
local stringy = require "stringy"

local _M = {}

-- returns the full path to the dnsmasq pid-file from the config
-- @param kong_config The config to construct the pid location from
function _M.pid_file(kong_config)
  return kong_config.nginx_working_dir..(stringy.endswith(kong_config.nginx_working_dir, "/") and "" or "/")..constants.CLI.DNSMASQ_PID
end

function _M.stop(kong_config)
  local _, code = IO.kill_process_by_pid_file(_M.pid_file(kong_config))
  if code and code == 0 then
    cutils.logger:info("dnsmasq stopped")
  end
end

function _M.is_running(kong_config)
  return IO.is_running_by_pid_file(_M.pid_file(kong_config))
end


function _M.start(kong_config)
  local cmd = IO.cmd_exists("dnsmasq") and "dnsmasq"

  if not cmd then -- Load dnsmasq given the PATH settings
    local env_path = (os.getenv("PATH")..":" or "").."/usr/local/sbin:/usr/sbin" -- Also check in default paths
    local paths = stringy.split(env_path, ":")
    for _, path in ipairs(paths) do
      if IO.file_exists(path..(stringy.endswith(path, "/") and "" or "/").."dnsmasq") then
        cmd = path.."/dnsmasq"
        break
      end
    end
  end

  if not cmd then
    cutils.logger:error_exit("Can't find dnsmasq")
  end

  -- Start the dnsmasq daemon
  local res, code = IO.os_execute(cmd.." -p "..kong_config.dns_resolver.port.." --pid-file=".._M.pid_file(kong_config).." -N -o")
  if code ~= 0 then
    cutils.logger:error_exit(res)
  else
    cutils.logger:info("dnsmasq started ("..cmd..")")
  end
end

return _M