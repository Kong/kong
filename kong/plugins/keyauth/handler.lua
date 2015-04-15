local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.keyauth.access"

local KeyAuthHandler = BasePlugin:extend()

function KeyAuthHandler:new()
  KeyAuthHandler.super.new(self, "keyauth")
end

function KeyAuthHandler:access(conf)
  KeyAuthHandler.super.access(self)
  access.execute(conf)
end

KeyAuthHandler.PRIORITY = 1000

return KeyAuthHandler
