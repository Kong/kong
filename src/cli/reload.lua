#!/usr/bin/env lua

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local signal = require "kong.cli.utils.signal"
local args = require("lapp")(string.format([[
Gracefully reload Kong applying any configuration changes (including nginx)

Usage: kong reload [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

signal.prepare_kong(args.config)

if signal.send_signal(args.config, "reload") then
  cutils.logger:success("Reloaded")
else
  cutils.logger:error_exit("Could not reload Kong")
end
