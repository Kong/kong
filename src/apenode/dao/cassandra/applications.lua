local BaseDao = require "apenode.dao.cassandra.base_dao"

local SCHEMA = {
  { _ = "id", type = "id" },
  { _ = "account_id", type = "id", required = true, exists = true },
  { _ = "public_key", required = false },
  { _ = "secret_key", required = true, unique = true },
  { _ = "created_at", type = "timestamp" }
}

local Applications = BaseDao:extend()

function Applications:new(database, properties)
  self._schema = SCHEMA
  self._queries = {
    insert = [[
      INSERT INTO applications(id, account_id, public_key, secret_key, created_at)
        VALUES(?, ?, ?, ?, ?);
    ]],
    exists = {
      account_id = [[ SELECT id FROM accounts WHERE id = ?; ]]
    },
    unique = {
      secret_key = [[ SELECT id FROM applications WHERE secret_key = ?; ]]
    }
  }

  Applications.super.new(self, database)
end

return Applications
