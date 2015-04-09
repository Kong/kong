#!/usr/bin/env lua

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local signal = require "kong.cli.utils.signal"
local args = require("lapp")(string.format([[
Usage: kong restart [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

if signal.is_running(args.config) then
  if not signal.send_signal(args.config, "stop") then
    cutils.logger:error_exit("Could not stop Kong")
  end
end

signal.prepare_kong(args.config)

if not signal.send_signal(args.config) then
  cutils.logger:error_exit("Could not restart Kong")
end

cutils.logger:success("Restarted")
