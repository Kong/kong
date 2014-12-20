local BaseDao = require "apenode.dao.sqlite.base_dao"
local PluginModel = require "apenode.models.plugin"

local Plugins = BaseDao:extend()

function Plugins:new(database)
  Plugins.super:new(database, PluginModel._COLLECTION, PluginModel._SCHEMA)
end

return Plugins
