local json = require "cjson"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log_serializers.basic"

local FileLogHandler = BasePlugin:extend()

function FileLogHandler:new()
  FileLogHandler.super.new(self, "filelog")
end

function FileLogHandler:log(conf)
  FileLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  ngx.log(ngx.INFO, json.encode(message))
end

return FileLogHandler
