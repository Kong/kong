local BaseDao = require "kong.dao.cassandra.base_dao"
local constants = require "kong.constants"

local SCHEMA = {
  id = { type = constants.DATABASE_TYPES.ID },
  provider_id = { type = "string", unique = true, queryable = true },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local Accounts = BaseDao:extend()

function Accounts:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "provider_id", "created_at" },
      query = [[ INSERT INTO accounts(id, provider_id, created_at) VALUES(?, ?, ?); ]]
    },
    update = {
      params = { "provider_id", "created_at", "id" },
      query = [[ UPDATE accounts SET provider_id = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM accounts %s; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM accounts WHERE id = ?; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM accounts WHERE id = ?; ]]
    },
    __unique = {
      provider_id ={
        params = { "provider_id" },
        query = [[ SELECT id FROM accounts WHERE provider_id = ?; ]]
      }
    }
  }

  Accounts.super.new(self, properties)
end

return Accounts
