local BasePlugin = require "kong.plugins.base_plugin"


local WithMigrationHandler = BasePlugin:extend()


WithMigrationHandler.PRIORITY = 1000


function WithMigrationHandler:new()
  WithMigrationHandler.super.new(self, "with-migration")
end


return WithMigrationHandler
