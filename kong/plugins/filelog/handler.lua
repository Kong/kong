local log = require "kong.plugins.filelog.log"
local BasePlugin = require "kong.plugins.base_plugin"

local FileLogHandler = BasePlugin:extend()

function FileLogHandler:new()
  FileLogHandler.super.new(self, "filelog")
end

function FileLogHandler:log(conf)
  FileLogHandler.super.log(self)
  log.execute(conf)
end

FileLogHandler.PRIORITY = 1

return FileLogHandler
