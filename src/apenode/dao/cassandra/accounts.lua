local BaseDao = require "apenode.dao.cassandra.base_dao"

local SCHEMA = {
  id = { type = "id" },
  provider_id = { unique = true },
  created_at = { type = "timestamp" }
}

local Accounts = BaseDao:extend()

function Accounts:new(database)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "provider_id", "created_at" },
      query = [[ INSERT INTO accounts(id, provider_id, created_at) VALUES(?, ?, ?); ]]
    },
    unique = {
      provider_id ={
        params = { "provider_id" },
        query = [[ SELECT id FROM accounts WHERE provider_id = ?; ]]
      }
    }
  }

  Accounts.super.new(self, database)
end

return Accounts
