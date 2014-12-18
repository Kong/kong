local BaseDao = require "apenode.dao.sqlite.base_dao"
local PluginModel = require "apenode.models.plugin"

local Plugins = {}
Plugins.__index = Plugins

setmetatable(Plugins, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Plugins:_init(database)
  BaseDao._init(self, database, PluginModel._COLLECTION, PluginModel._SCHEMA)
end

return Plugins
