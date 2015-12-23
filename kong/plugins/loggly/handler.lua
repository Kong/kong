local log = require "kong.plugins.loggly.log"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"

local LogglyLogHandler = BasePlugin:extend()

function LogglyLogHandler:new()
  LogglyLogHandler.super.new(self, "loggly")
end

function LogglyLogHandler:log(conf)
  LogglyLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  log.execute(conf, message)
end

LogglyLogHandler.PRIORITY = 1

return LogglyLogHandler
