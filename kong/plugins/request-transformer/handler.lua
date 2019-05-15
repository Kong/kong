local access = require "kong.plugins.request-transformer.access"

local RequestTransformerHandler = {}

function RequestTransformerHandler:access(conf)
  access.execute(conf)
end

RequestTransformerHandler.PRIORITY = 801
RequestTransformerHandler.VERSION = "2.0.0"

return RequestTransformerHandler
