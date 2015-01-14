local BaseDao = require "apenode.dao.cassandra.base_dao"
local PluginModel = require "apenode.models.plugin"

local Plugins = BaseDao:extend()

function Plugins:new(client)
  Plugins.super.new(self, client, PluginModel._COLLECTION, PluginModel._SCHEMA)
end

return Plugins
