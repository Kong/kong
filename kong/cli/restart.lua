#!/usr/bin/env luajit

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local signal = require "kong.cli.utils.signal"
local args = require("lapp")(string.format([[
Restart the Kong instance running in the configured 'nginx_working_dir'.

Kong will be shutdown before restarting. For a zero-downtime reload
of your configuration, look at 'kong reload'.

Usage: kong restart [options]

Options:
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

if signal.is_running(args.config) then
  if not signal.send_signal(args.config, signal.STOP) then
    cutils.logger:error_exit("Could not stop Kong")
  end
end

signal.prepare_kong(args.config)

if not signal.send_signal(args.config) then
  cutils.logger:error_exit("Could not restart Kong")
end

cutils.logger:success("Restarted")
