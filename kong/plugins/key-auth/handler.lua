local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.key-auth.access"

local KeyAuthHandler = BasePlugin:extend()

function KeyAuthHandler:new()
  KeyAuthHandler.super.new(self, "key-auth")
end

function KeyAuthHandler:access(conf)
  KeyAuthHandler.super.access(self)
  access.execute(conf)
end

KeyAuthHandler.PRIORITY = 1000

return KeyAuthHandler
