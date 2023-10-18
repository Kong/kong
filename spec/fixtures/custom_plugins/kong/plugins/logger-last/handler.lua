-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local LoggerHandler = require "spec.fixtures.custom_plugins.kong.plugins.logger.handler"

local LoggerLastHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 0,
}


LoggerLastHandler.init_worker   = LoggerHandler.init_worker
LoggerLastHandler.configure     = LoggerHandler.configure
LoggerLastHandler.certificate   = LoggerHandler.certificate
LoggerLastHandler.preread       = LoggerHandler.preread
LoggerLastHandler.rewrite       = LoggerHandler.rewrite
LoggerLastHandler.access        = LoggerHandler.access
LoggerLastHandler.header_filter = LoggerHandler.header_filter
LoggerLastHandler.body_filter   = LoggerHandler.body_filter
LoggerLastHandler.log           = LoggerHandler.log


return LoggerLastHandler
