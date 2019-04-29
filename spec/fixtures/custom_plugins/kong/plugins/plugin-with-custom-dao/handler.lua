local BasePlugin = require "kong.plugins.base_plugin"


local MyHandler = BasePlugin:extend()


MyHandler.PRIORITY = 1000


function MyHandler:new()
  MyHandler.super.new(self, "plugin-with-custom-dao")
end


return MyHandler
