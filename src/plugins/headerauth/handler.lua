-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.headerauth.access"

local HeaderAuthHandler = BasePlugin:extend()

function HeaderAuthHandler:new()
  HeaderAuthHandler.super.new(self, "headerauth")
end

function HeaderAuthHandler:access(conf)
  HeaderAuthHandler.super.access(self)
  access.execute(conf)
end

HeaderAuthHandler.PRIORITY = 1000

return HeaderAuthHandler
