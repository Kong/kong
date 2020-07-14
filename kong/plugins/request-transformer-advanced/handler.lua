local access = require "kong.plugins.request-transformer-advanced.access"


local RequestTransformerHandler = {}


function RequestTransformerHandler:access(conf)
  access.execute(conf)
end


RequestTransformerHandler.VERSION  = "0.37.2"
RequestTransformerHandler.PRIORITY = 802


return RequestTransformerHandler
