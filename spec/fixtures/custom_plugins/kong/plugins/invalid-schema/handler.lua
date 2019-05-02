local BasePlugin = require "kong.plugins.base_plugin"


local InvalidSchemaHandler = BasePlugin:extend()


InvalidSchemaHandler.PRIORITY = 1000


function InvalidSchemaHandler:new()
  InvalidSchemaHandler.super.new(self, "invalid-schema")
end


return InvalidSchemaHandler
