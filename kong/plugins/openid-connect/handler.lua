local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"


local OICHandler = BasePlugin:extend()

function OICHandler:new()
  OICHandler.super.new(self, "openid-connect")
end


function OICHandler:init_worker()
  OICHandler.super.init_worker(self)
end


function OICHandler:access()
  OICHandler.super.access(self)
  return responses.send_NOT_FOUND()
end


OICHandler.PRIORITY = 1000


return OICHandler
