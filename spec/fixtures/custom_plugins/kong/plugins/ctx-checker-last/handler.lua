local BasePlugin = require "kong.plugins.base_plugin"
local CtxCheckerHandler = require "spec.fixtures.custom_plugins.kong.plugins.ctx-checker.handler"


local CtxCheckerLastHandler = BasePlugin:extend()


-- This plugin is a copy of ctx checker with a lower priority (it will run last)
CtxCheckerLastHandler.PRIORITY = 0


function CtxCheckerLastHandler:new()
  CtxCheckerLastHandler.super.new(self, "ctx-checker-last")
end


CtxCheckerLastHandler.access = CtxCheckerHandler.access
CtxCheckerLastHandler.header_filter = CtxCheckerHandler.header_filter


return CtxCheckerLastHandler
