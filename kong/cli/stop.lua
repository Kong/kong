#!/usr/bin/env lua

local constants = require "kong.constants"
local stop = require "kong.cli.utils.stop"
local args = require("lapp")(string.format([[
Usage: kong stop [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

stop(args.config)
