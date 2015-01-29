local BaseDao = require "apenode.dao.cassandra.base_dao"

local SCHEMA = {
  { _ = "id", type = "id" },
  { _ = "provider_id", unique = true },
  { _ = "created_at", type = "timestamp" }
}

local Accounts = BaseDao:extend()

function Accounts:new(database)
  self._schema = SCHEMA
  self._queries = {
    insert = [[
      INSERT INTO accounts(id, provider_id, created_at) VALUES(?, ?, ?);
    ]],
    unique = {
      provider_id = [[ SELECT id FROM accounts WHERE provider_id = ?; ]]
    }
  }

  Accounts.super.new(self, database)
end

return Accounts
