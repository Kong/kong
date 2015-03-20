-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local log = require "kong.plugins.udplog.log"

local UdpLogHandler = BasePlugin:extend()

function UdpLogHandler:new()
  UdpLogHandler.super.new(self, "udplog")
end

function UdpLogHandler:log(conf)
  UdpLogHandler.super.log(self)
  log.execute(conf)
end

return UdpLogHandler
