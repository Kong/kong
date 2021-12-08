local access = require "kong.plugins.request-transformer.access"


local RequestTransformerHandler = {
  VERSION  = "1.3.3",
  PRIORITY = 801,
}


function RequestTransformerHandler:access(conf)
  access.execute(conf)
end


return RequestTransformerHandler
