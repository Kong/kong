local BasePlugin = require "kong.plugins.base_plugin"


local LegacyPluginGoodHandler = BasePlugin:extend()


LegacyPluginGoodHandler.PRIORITY = 1000


function LegacyPluginGoodHandler:new()
  LegacyPluginGoodHandler.super.new(self, "legacy-plugin-good")
end


return LegacyPluginGoodHandler
