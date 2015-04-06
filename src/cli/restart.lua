#!/usr/bin/env lua

local constants = require "kong.constants"
local signal = require "kong.cli.utils.signal"
local args = require("lapp")(string.format([[
Usage: kong restart [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

signal.send_stop(args.config)
signal.send_start(args.config)
