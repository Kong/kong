local BasePlugin = require "kong.plugins.base_plugin"


local SlowQueryHandler = BasePlugin:extend()


SlowQueryHandler.PRIORITY = 1000


function SlowQueryHandler:new()
  SlowQueryHandler.super.new(self, "slow-query")
end


return SlowQueryHandler
