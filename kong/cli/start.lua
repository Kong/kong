#!/usr/bin/env lua

local constants = require "kong.constants"
local start = require "kong.cli.utils.start"
local args = require("lapp")(string.format([[
Usage: kong start [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

start(args.config)
