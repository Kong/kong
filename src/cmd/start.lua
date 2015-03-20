#!/usr/bin/env lua

local utils = require "kong.cmd.utils"
local args = require "lapp" [[

Usage: kong start [options]

Options:
  -c,--config (default kong.yml)  configuration file
  -o,--output (default nginx_tmp) nginx output
]]

local nginx_path = utils.find_nginx()
if not nginx_path then
  utils.logger:error_exit("can't find nginx")
end

local nginx_config = utils.prepare_nginx_output(args.config, args.output)

local cmd = "KONG_CONF="..args.config.." "..nginx_path.." -p "..args.output.." -c '"..nginx_config.."'"
if args.daemon then
  cmd = cmd.." > /dev/null 2>&1 &"
end

return os.execute(cmd)
