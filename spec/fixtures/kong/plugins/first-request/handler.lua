local BasePlugin = require "kong.plugins.base_plugin"
local cache = require "kong.tools.database_cache"

local FirstRequestHandler = BasePlugin:extend()

FirstRequestHandler.PRIORITY = 1000

function FirstRequestHandler:new()
  FirstRequestHandler.super.new(self, "first-request")
end

function FirstRequestHandler:access(conf)
  FirstRequestHandler.super.access(self)

  cache.set("requested", {requested = true})
end

return FirstRequestHandler