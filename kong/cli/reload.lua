#!/usr/bin/env luajit

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local signal = require "kong.cli.utils.signal"
local args = require("lapp")(string.format([[
Gracefully reload the Kong instance running in the configured 'nginx_working_dir'.

Any configuration change will be applied.

Usage: kong reload [options]

Options:
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

if not signal.is_running(args.config) then
  cutils.logger:error_exit("Could not reload: Kong is not running.")
end

signal.prepare_kong(args.config, signal.RELOAD)

if signal.send_signal(args.config, signal.RELOAD) then
  cutils.logger:success("Reloaded")
else
  cutils.logger:error_exit("Could not reload Kong")
end
