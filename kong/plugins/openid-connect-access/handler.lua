local BasePlugin = require "kong.plugins.base_plugin"

local OICAccessHandler = BasePlugin:extend()

function OICAccessHandler:new()
  OICAccessHandler.super.new(self, "openid-connect-access")
end


function OICAccessHandler:init_worker(conf)
  OICAccessHandler.super.init_worker(self)

  -- check here

end


function OICAccessHandler:access(conf)
  OICAccessHandler.super.access(self)

  -- check here

end

OICAccessHandler.PRIORITY = 1000

return OICAccessHandler
