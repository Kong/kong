local log = require "kong.plugins.syslog.log"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"

local SysLogHandler = BasePlugin:extend()

function SysLogHandler:new()
  SysLogHandler.super.new(self, "syslog")
end

function SysLogHandler:log(conf)
  SysLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  log.execute(conf, message)
end

SysLogHandler.PRIORITY = 1

return SysLogHandler
