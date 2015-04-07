#!/usr/bin/env lua

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local signal = require "kong.cli.utils.signal"
local args = require("lapp")(string.format([[
Graceful shutdown

Usage: kong stop [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

if signal.send_signal(args.config, "quit") then
  cutils.logger:success("Stopped")
else
  cutils.logger:error_exit("Could not gracefully stop Kong")
end
