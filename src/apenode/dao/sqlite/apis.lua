local BaseDao = require "apenode.dao.sqlite.base_dao"
local ApiModel = require "apenode.models.api"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Apis:_init(database)
  BaseDao._init(self, database, ApiModel._COLLECTION, ApiModel._SCHEMA)
end

return Apis
