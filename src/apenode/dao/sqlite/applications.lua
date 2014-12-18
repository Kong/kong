local BaseDao = require "apenode.dao.sqlite.base_dao"
local ApplicationsModel = require "apenode.models.application"

local Applications = {}
Applications.__index = Applications

setmetatable(Applications, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Applications:_init(database)
  BaseDao._init(self, database, ApplicationsModel._COLLECTION, ApplicationsModel._SCHEMA)
end

return Applications
