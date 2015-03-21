#!/usr/bin/env lua

local cutils = require "kong.cmd.utils"
local args = require("lapp")(string.format([[

Usage: kong start [options]

Options:
  -c,--config (default %s) configuration file
]], cutils.CONSTANTS.GLOBAL_KONG_CONF))

-- Make sure nginx is there and is openresty
local nginx_path = cutils.find_nginx()
if not nginx_path then
  cutils.logger:error_exit("can't find nginx")
end

-- Get configuration from default or given path
local config_path, config = cutils.get_kong_config(args.config)

local nginx_working_dir = cutils.prepare_nginx_working_dir(config)
local cmd = string.format("KONG_CONF=%s %s -p %s -c %s -g 'pid %s;'",
                          config_path,
                          nginx_path,
                          nginx_working_dir,
                          cutils.CONSTANTS.NGINX_CONFIG,
                          cutils.CONSTANTS.NGINX_PID)

if os.execute(cmd) == 0 then
  cutils.logger:success("Started")
else
  cutils.logger:error("Could not start Kong")
end
