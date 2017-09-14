-- a plugin fixture to test running of the rewrite phase handler.

local BasePlugin = require "kong.plugins.base_plugin"

local Rewriter = BasePlugin:extend()

Rewriter.PRIORITY = 1000

function Rewriter:new()
  Rewriter.super.new(self, "rewriter")
end

function Rewriter:rewrite(conf)
  Rewriter.super.access(self)

  ngx.req.set_header("rewriter", conf.value)
end

return Rewriter
