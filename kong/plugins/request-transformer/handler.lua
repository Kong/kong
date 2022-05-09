local access = require "kong.plugins.request-transformer.access"
local kong_meta = require "kong.meta"


local RequestTransformerHandler = {
  VERSION = kong_meta._VERSION,
  PRIORITY = 801,
}


function RequestTransformerHandler:access(conf)
  access.execute(conf)
end


return RequestTransformerHandler
