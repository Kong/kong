local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.request-transformer.access"

local RequestTransformerHandler = BasePlugin:extend()

function RequestTransformerHandler:new()
  RequestTransformerHandler.super.new(self, "request-transformer")
end

function RequestTransformerHandler:access(conf)
  RequestTransformerHandler.super.access(self)
  access.execute(conf)
end

RequestTransformerHandler.PRIORITY = 990

return RequestTransformerHandler
