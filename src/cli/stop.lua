#!/usr/bin/env lua

local cutils = require "kong.cli.utils"
local constants = require "kong.constants"
local args = require("lapp")(string.format([[
Usage: kong stop [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

-- Get configuration from default or given path
local config_path = cutils.get_kong_config_path(args.config)
local config = cutils.load_configuration_and_dao(config_path)

local pid = cutils.path:join(config.nginx_working_dir, constants.CLI.NGINX_PID)

if not cutils.file_exists(pid) then
 cutils.logger:error_exit("Not running. Could not find pid at: "..pid)
end

local cmd = "kill -QUIT $(cat "..pid..")"

if os.execute(cmd) == 0 then
  cutils.logger:success("Stopped")
end
