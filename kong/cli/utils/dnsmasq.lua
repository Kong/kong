local IO = require "kong.tools.io"
local cutils = require "kong.cli.utils"
local constants = require "kong.constants"
local stringy = require "stringy"

local _M = {}

function _M.stop(kong_config)
  local pid_file = kong_config.nginx_working_dir.."/"..constants.CLI.DNSMASQ_PID
  local _, code = IO.kill_process_by_pid_file(pid_file)
  if code and code == 0 then
    cutils.logger:info("dnsmasq stopped")
  end
end

function _M.start(kong_config)
  local cmd = IO.cmd_exists("dnsmasq") and "dnsmasq" or
                (IO.cmd_exists("/usr/local/sbin/dnsmasq") and "/usr/local/sbin/dnsmasq" or nil) -- On OS X dnsmasq is at /usr/local/sbin/
  if not cmd then
    cutils.logger:error_exit("Can't find dnsmasq")
  end

  -- Start the dnsmasq daemon
  local file_pid = kong_config.nginx_working_dir..(stringy.endswith(kong_config.nginx_working_dir, "/") and "" or "/")..constants.CLI.DNSMASQ_PID
  local res, code = IO.os_execute(cmd.." -p "..kong_config.dnsmasq_port.." --pid-file="..file_pid.." -N -o")
  if code ~= 0 then
    cutils.logger:error_exit(res)
  else
    cutils.logger:info("dnsmasq started")
  end
end

return _M