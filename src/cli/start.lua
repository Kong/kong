#!/usr/bin/env lua

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local signal = require "kong.cli.utils.signal"
local args = require("lapp")(string.format([[
Usage: kong start [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

if signal.send_signal(args.config) then
  cutils.logger:success("Started")
else
  cutils.logger:error_exit("Could not start Kong")
end
