local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.gelato.access"

local GelatoHandler = BasePlugin:extend()

function GelatoHandler:new()
  GelatoHandler.super.new(self, "gelato")
end

function GelatoHandler:access(conf)
  GelatoHandler.super.access(self)
  access.execute(conf)
end

GelatoHandler.PRIORITY = 2000

return GelatoHandler
