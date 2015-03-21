#!/usr/bin/env lua

local cutils = require "kong.cmd.utils"
local args = require("lapp")(string.format([[

Usage: kong stop [options]

Options:
  -c,--config (default %s) configuration file
]], cutils.CONSTANTS.GLOBAL_KONG_CONF))

-- Get configuration from default or given path
local config_path, config = cutils.get_kong_config(args.config)

local pid = cutils.path:join(config.nginx_working_dir, cutils.CONSTANTS.NGINX_PID)

if not cutils.file_exists(pid) then
 cutils.logger:error("Not running. Could not find pid at: "..pid)
 os.exit(1)
end

local cmd = "kill -QUIT $(cat "..pid..")"

if os.execute(cmd) == 0 then
  cutils.logger:success("Stopped")
end
