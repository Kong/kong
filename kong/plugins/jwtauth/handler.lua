local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.jwtauth.access"

local JwtAuthHandler = BasePlugin:extend()

function JwtAuthHandler:new()
  JwtAuthHandler.super.new(self, "JwtAuth")
end

function JwtAuthHandler:access(conf)
  JwtAuthHandler.super.access(self)
  access.execute(conf)
end

JwtAuthHandler.PRIORITY = 1000

return JwtAuthHandler
