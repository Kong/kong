local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.request-transformer.access"


local feature_flag_limit_body = require "kong.plugins.request-transformer.feature_flags.limit_body"


local RequestTransformerHandler = BasePlugin:extend()

function RequestTransformerHandler:new()
  RequestTransformerHandler.super.new(self, "request-transformer")
end


function RequestTransformerHandler:init_worker()
  RequestTransformerHandler.super.init_worker(self, "request-transformer")

  feature_flag_limit_body.init_worker()
end


function RequestTransformerHandler:access(conf)
  RequestTransformerHandler.super.access(self)
  access.execute(conf)
end

RequestTransformerHandler.PRIORITY = 801
RequestTransformerHandler.VERSION = "0.1.0"

return RequestTransformerHandler
