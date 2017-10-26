local BasePlugin = require "kong.plugins.base_plugin"


local CtxCheckerHandler = BasePlugin:extend()


CtxCheckerHandler.PRIORITY = 1000


function CtxCheckerHandler:new()
  CtxCheckerHandler.super.new(self, "ctx-checker")
end


function CtxCheckerHandler:access(conf)
  CtxCheckerHandler.super.access(self)

  if conf.ctx_field then
    if ngx.ctx[conf.ctx_field] then
      ngx.req.set_header("Ctx-Checker-Plugin-Field", ngx.ctx[conf.ctx_field])
    end
  end
end


return CtxCheckerHandler
