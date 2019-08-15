local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.request-transformer-advanced.access"

local RequestTransformerHandler = BasePlugin:extend()

function RequestTransformerHandler:new()
  RequestTransformerHandler.super.new(self, "request-transformer-advanced")
end


function RequestTransformerHandler:access(conf)
  RequestTransformerHandler.super.access(self)
  access.execute(conf)
end

RequestTransformerHandler.PRIORITY = 802
RequestTransformerHandler.VERSION = "0.35.1"

return RequestTransformerHandler
