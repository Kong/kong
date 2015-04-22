local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.cors.access"

local CorsHandler = BasePlugin:extend()

function CorsHandler:new()
  CorsHandler.super.new(self, "cors")
end

function CorsHandler:access(conf)
  CorsHandler.super.access(self)
  access.execute(conf)
end

CorsHandler.PRIORITY = 2000

return CorsHandler