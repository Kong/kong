-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local CtxCheckerHandler = require "spec.fixtures.custom_plugins.kong.plugins.ctx-checker.handler"


local CtxCheckerLastHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 0,
  _name = "ctx-checker-last",
}


CtxCheckerLastHandler.access = CtxCheckerHandler.access
CtxCheckerLastHandler.header_filter = CtxCheckerHandler.header_filter


return CtxCheckerLastHandler
