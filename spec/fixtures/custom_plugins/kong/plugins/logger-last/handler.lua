local BasePlugin = require "kong.plugins.base_plugin"
local LoggerHandler = require "spec.fixtures.custom_plugins.kong.plugins.logger.handler"

local LoggerLastHandler = BasePlugin:extend()


LoggerLastHandler.PRIORITY = 0


function LoggerLastHandler:new()
  LoggerLastHandler.super.new(self, "logger-last")
end


LoggerLastHandler.init_worker   = LoggerHandler.init_worker
LoggerLastHandler.certificate   = LoggerHandler.certificate
LoggerLastHandler.access        = LoggerHandler.access
LoggerLastHandler.rewrite       = LoggerHandler.rewrite
LoggerLastHandler.header_filter = LoggerHandler.header_filter
LoggerLastHandler.body_filter   = LoggerHandler.body_filter
LoggerLastHandler.log           = LoggerHandler.log


return LoggerLastHandler

