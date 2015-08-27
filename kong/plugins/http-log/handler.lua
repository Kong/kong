local basic_serializer = require "kong.plugins.log-serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"
local log = require "kong.plugins.http-log.log"

local HttpLogHandler = BasePlugin:extend()

function HttpLogHandler:new()
  HttpLogHandler.super.new(self, "http-log")
end

function HttpLogHandler:log(conf)
  HttpLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  log.execute(conf, message)
end

HttpLogHandler.PRIORITY = 1

return HttpLogHandler
