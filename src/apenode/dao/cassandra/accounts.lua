local BaseDao = require "apenode.dao.cassandra.base_dao"
local AccountModel = require "apenode.models.account"

local Accounts = BaseDao:extend()

function Accounts:new(database, properties)
  Accounts.super.new(self, database, AccountModel._COLLECTION, AccountModel._SCHEMA, properties)
end

return Accounts
