local BasePlugin = require "kong.plugins.base_plugin"

local OICRevocationHandler = BasePlugin:extend()

function OICRevocationHandler:new()
  OICRevocationHandler.super.new(self, "openid-connect-revocation")
end


function OICRevocationHandler:init_worker()
  OICRevocationHandler.super.init_worker(self)
end


function OICRevocationHandler:access()
  OICRevocationHandler.super.access(self)
end


OICRevocationHandler.PRIORITY = 1000


return OICRevocationHandler
