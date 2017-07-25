local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.oauth2.access"

local OAuthHandler = BasePlugin:extend()

function OAuthHandler:new()
  OAuthHandler.super.new(self, "oauth2")
end

function OAuthHandler:access(conf)
  OAuthHandler.super.access(self)
  access.execute(conf)
end

OAuthHandler.PRIORITY = 1800

return OAuthHandler
