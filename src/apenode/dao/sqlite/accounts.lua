local BaseDao = require "apenode.dao.sqlite.base_dao"
local AccountModel = require "apenode.models.account"

local Accounts = {}
Accounts.__index = Accounts

setmetatable(Accounts, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Accounts:_init(database)
  BaseDao._init(self, database, AccountModel._COLLECTION, AccountModel._SCHEMA)
end

return Accounts
