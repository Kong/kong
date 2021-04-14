-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
