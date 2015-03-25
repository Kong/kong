#!/usr/bin/env lua

local constants = require "kong.constants"
local start = require "kong.cli.utils.start"
local stop = require "kong.cli.utils.stop"
local args = require("lapp")(string.format([[
Usage: kong restart [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

stop(args.config)
start(args.config)
