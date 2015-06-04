local BasePlugin = require "kong.plugins.base_plugin"
local log = require "kong.plugins.httplog.log"

local HttpLogHandler = BasePlugin:extend()

function HttpLogHandler:new()
  HttpLogHandler.super.new(self, "httplog")
end

function HttpLogHandler:log(conf)
  HttpLogHandler.super.log(self)
  log.execute(conf)
end

return HttpLogHandler
