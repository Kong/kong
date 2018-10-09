-- Copyright (C) Kong Inc.
local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.hmac-auth.access"


local HMACAuthHandler = BasePlugin:extend()


function HMACAuthHandler:new()
  HMACAuthHandler.super.new(self, "hmac-auth")
end


function HMACAuthHandler:access(conf)
  HMACAuthHandler.super.access(self)
  access.execute(conf)
end


HMACAuthHandler.PRIORITY = 1000
HMACAuthHandler.VERSION = "0.2.0"


return HMACAuthHandler
