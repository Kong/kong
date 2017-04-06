local BasePlugin = require "kong.plugins.base_plugin"

local RewriteHandler = BasePlugin:extend()

RewriteHandler.PRIORITY = 1000

function RewriteHandler:new()
  RewriteHandler.super.new(self, "first-request")
end

function RewriteHandler:rewrite(conf)
  RewriteHandler.super.rewrite(self)

  local args = ngx.req.get_uri_args()
  ngx.req.set_uri(args.rewrite_to)
end

return RewriteHandler