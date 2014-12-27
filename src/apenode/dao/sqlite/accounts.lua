local BaseDao = require "apenode.dao.sqlite.base_dao"
local AccountModel = require "apenode.models.account"

local Accounts = BaseDao:extend()

function Accounts:new(database)
  Accounts.super.new(self, database, AccountModel._COLLECTION, AccountModel._SCHEMA)
end

return Accounts
