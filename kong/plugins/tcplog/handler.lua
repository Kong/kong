local BasePlugin = require "kong.plugins.base_plugin"
local log = require "kong.plugins.tcplog.log"

local TcpLogHandler = BasePlugin:extend()

function TcpLogHandler:new()
  TcpLogHandler.super.new(self, "tcplog")
end

function TcpLogHandler:log(conf)
  TcpLogHandler.super.log(self)
  log.execute(conf)
end

return TcpLogHandler
