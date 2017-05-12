local BasePlugin = require "kong.plugins.base_plugin"

local OICAuthenticationHandler = BasePlugin:extend()

function OICAuthenticationHandler:new()
  OICAuthenticationHandler.super.new(self, "openid-connect-authentication")
end


function OICAuthenticationHandler:init_worker(conf)
  OICAuthenticationHandler.super.init_worker(self)

  -- check here

end


function OICAuthenticationHandler:access(conf)
  OICAuthenticationHandler.super.access(self)

  -- check here

end

OICAuthenticationHandler.PRIORITY = 1000

return OICAuthenticationHandler
