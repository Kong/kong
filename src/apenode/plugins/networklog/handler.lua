-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local log = require "apenode.plugins.networklog.log"

local NetworkLogHandler = BasePlugin:extend()

function NetworkLogHandler:new()
  NetworkLogHandler.super.new(self, "networklog")
end

function NetworkLogHandler:log(conf)
  NetworkLogHandler.super.log(self)
  log.execute(conf)
end

return NetworkLogHandler
