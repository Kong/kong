local log = require "kong.plugins.logentries.log"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"

local LogentriesHandler = BasePlugin:extend()

function LogentriesHandler:new()
  LogentriesHandler.super.new(self, "logentries")
end

function LogentriesHandler:log(conf)
  LogentriesHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  log.execute(conf, message)
end

return LogentriesHandler
