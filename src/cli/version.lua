#!/usr/bin/env lua

local cutils = require "kong.cli.utils"
local infos = cutils.get_infos()

cutils.logger:log(string.format("Kong version: %s", infos.version))
