#!/usr/bin/env lua

local cutils = require "kong.cli.utils"
local infos = cutils.get_kong_infos()

cutils.logger:info(string.format("Kong version: %s", infos.version))
