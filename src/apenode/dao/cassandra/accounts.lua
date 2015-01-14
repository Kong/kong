local BaseDao = require "apenode.dao.cassandra.base_dao"
local AccountModel = require "apenode.models.account"

local Accounts = BaseDao:extend()

function Accounts:new(client)
  Accounts.super.new(self, client, AccountModel._COLLECTION, AccountModel._SCHEMA)
end

return Accounts
