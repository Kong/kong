-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.base_plugin"
local access = require "kong.plugins.basicauth.access"

local BasicAuthHandler = BasePlugin:extend()

function BasicAuthHandler:new()
  BasicAuthHandler.super.new(self, "basicauth")
end

function BasicAuthHandler:access(conf)
  BasicAuthHandler.super.access(self)
  access.execute(conf)
end

BasicAuthHandler.PRIORITY = 1000

return BasicAuthHandler
