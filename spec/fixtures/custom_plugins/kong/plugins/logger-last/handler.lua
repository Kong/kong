local LoggerHandler = require "spec.fixtures.custom_plugins.kong.plugins.logger.handler"

local LoggerLastHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 0,
}


LoggerLastHandler.init_worker   = LoggerHandler.init_worker
LoggerLastHandler.certificate   = LoggerHandler.certificate
LoggerLastHandler.preread       = LoggerHandler.preread
LoggerLastHandler.rewrite       = LoggerHandler.rewrite
LoggerLastHandler.access        = LoggerHandler.access
LoggerLastHandler.header_filter = LoggerHandler.header_filter
LoggerLastHandler.body_filter   = LoggerHandler.body_filter
LoggerLastHandler.log           = LoggerHandler.log


return LoggerLastHandler
