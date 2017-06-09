local BasePlugin = require "kong.plugins.base_plugin"

local OICHandler = BasePlugin:extend()

function OICHandler:new()
  OICHandler.super.new(self, "openid-connect")
end


function OICHandler:init_worker()
  OICHandler.super.init_worker(self)
end


function OICHandler:access()
  OICHandler.super.access(self)
end


OICHandler.PRIORITY = 1


return OICHandler
