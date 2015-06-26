local log = require "kong.plugins.udplog.log"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log_serializers.basic"

local UdpLogHandler = BasePlugin:extend()

function UdpLogHandler:new()
  UdpLogHandler.super.new(self, "udplog")
end

function UdpLogHandler:log(conf)
  UdpLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  log.execute(conf, message)
end

return UdpLogHandler
