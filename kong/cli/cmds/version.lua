#!/usr/bin/env luajit

local logger = require "kong.cli.utils.logger"
local meta = require "kong.meta"

logger:print(string.format("%s version: %s", meta._NAME, meta._VERSION))
