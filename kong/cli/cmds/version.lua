#!/usr/bin/env luajit

local logger = require "kong.cli.utils.logger"
local constants = require "kong.constants"

logger:print(string.format("Kong version: %s", constants.VERSION))
