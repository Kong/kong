local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.jwt.access"

local JwtHandler = BasePlugin:extend()

function JwtHandler:new()
  JwtHandler.super.new(self, "jwt")
end

function JwtHandler:access(conf)
  JwtHandler.super.access(self)
  access.execute(conf)
end

JwtHandler.PRIORITY = 1000

return JwtHandler
