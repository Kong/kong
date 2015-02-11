local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  id = { type = "id" },
  account_id = { type = "id", required = true, foreign = true, queryable = true },
  public_key = { required = true, unique = true, queryable = true },
  secret_key = { required = true },
  created_at = { type = "timestamp" }
}

local Applications = BaseDao:extend()

function Applications:new(database, properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "account_id", "public_key", "secret_key", "created_at" },
      query = [[
        INSERT INTO applications(id, account_id, public_key, secret_key, created_at)
          VALUES(?, ?, ?, ?, ?);
      ]]
    },
    update = {
      params = { "public_key", "secret_key", "created_at", "id" },
      query = [[ UPDATE applications SET public_key = ?, secret_key = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM applications %s; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM applications WHERE id = ?; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM applications WHERE id = ?; ]]
    },
    __foreign = {
      account_id = {
        params = { "account_id" },
        query = [[ SELECT id FROM accounts WHERE id = ?; ]]
      }
    },
    __unique = {
      public_key = {
        params = { "public_key" },
        query = [[ SELECT id FROM applications WHERE public_key = ?; ]]
      }
    }
  }

  Applications.super.new(self, database)
end

return Applications
