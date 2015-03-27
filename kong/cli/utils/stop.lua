local IO = require "kong.tools.io"
local cutils = require "kong.cli.utils"
local constants = require "kong.constants"

local _M = {}

function _M.stop(args_config)
  -- Get configuration from default or given path
  local config_path = cutils.get_kong_config_path(args_config)
  local config = IO.load_configuration_and_dao(config_path)

  local pid = IO.path:join(config.nginx_working_dir, constants.CLI.NGINX_PID)

  if not IO.file_exists(pid) then
   cutils.logger:error_exit("Not running. Could not find pid at: "..pid)
  end

  local cmd = "kill -QUIT $(cat "..pid..")"

  if os.execute(cmd) == 0 then
    cutils.logger:success("Stopped")
  end
end

return _M.stop
