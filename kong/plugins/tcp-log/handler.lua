local log = require "kong.plugins.tcp-log.log"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"

local TcpLogHandler = BasePlugin:extend()

function TcpLogHandler:new()
  TcpLogHandler.super.new(self, "tcp-log")
end

function TcpLogHandler:log(conf)
  TcpLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  log.execute(conf, message)
end

return TcpLogHandler
