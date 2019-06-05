local access = require "kong.plugins.request-transformer.access"


local RequestTransformerHandler = {
  VERSION  = "1.2.1",
  PRIORITY = 801,
}


function RequestTransformerHandler:access(conf)
  access.execute(conf)
end


return RequestTransformerHandler
