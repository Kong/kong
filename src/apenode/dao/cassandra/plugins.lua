local BaseDao = require "apenode.dao.cassandra.base_dao"
local PluginModel = require "apenode.models.plugin"

local Plugins = BaseDao:extend()

function Plugins:new(database, properties)
  Plugins.super.new(self, database, PluginModel._COLLECTION, PluginModel._SCHEMA, properties)
end

return Plugins
