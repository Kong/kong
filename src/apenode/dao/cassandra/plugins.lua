local BaseDao = require "apenode.dao.sqlite.base_dao"
local PluginModel = require "apenode.models.plugin"

local Plugins = BaseDao:extend()

function Plugins:new(configuration)
  Plugins.super.new(self, configuration, PluginModel._COLLECTION, PluginModel._SCHEMA)
end

return Plugins
