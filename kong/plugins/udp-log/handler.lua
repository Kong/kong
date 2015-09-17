local log = require "kong.plugins.udp-log.log"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"

local UdpLogHandler = BasePlugin:extend()

function UdpLogHandler:new()
  UdpLogHandler.super.new(self, "udp-log")
end

function UdpLogHandler:log(conf)
  UdpLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  log.execute(conf, message)
end

UdpLogHandler.PRIORITY = 1

return UdpLogHandler
