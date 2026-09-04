local CtxCheckerHandler = require "spec.fixtures.custom_plugins.kong.plugins.ctx-checker.handler"


local CtxCheckerLastHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 0,
  _name = "ctx-checker-last",
}


CtxCheckerLastHandler.access = CtxCheckerHandler.access
CtxCheckerLastHandler.header_filter = CtxCheckerHandler.header_filter


return CtxCheckerLastHandler
