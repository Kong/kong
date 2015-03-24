local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.queryauth.access"

local QueryAuthHandler = BasePlugin:extend()

function QueryAuthHandler:new()
  QueryAuthHandler.super.new(self, "queryauth")
end

function QueryAuthHandler:access(conf)
  QueryAuthHandler.super.access(self)
  access.execute(conf)
end

QueryAuthHandler.PRIORITY = 1000

return QueryAuthHandler
