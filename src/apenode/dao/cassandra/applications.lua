local BaseDao = require "apenode.dao.cassandra.base_dao"

local SCHEMA = {
  id = { type = "id" },
  account_id = { type = "id", required = true, exists = true },
  public_key = {},
  secret_key = { required = true, unique = true },
  created_at = { type = "timestamp" }
}

local Applications = BaseDao:extend()

function Applications:new(database, properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      all = {
        params = { "id", "account_id", "public_key", "secret_key", "created_at" },
        query = [[
          INSERT INTO applications(id, account_id, public_key, secret_key, created_at)
            VALUES(?, ?, ?, ?, ?);
        ]]
      },
      no_public_key = {
        params = { "id", "account_id", "secret_key", "created_at" },
        query = [[ INSERT INTO applications(id, account_id, secret_key, created_at)
                    VALUES(?, ?, ?, ?); ]]
      }
    },
    update = {
      params = { "account_id", "public_key", "secret_key", "created_at", "id" },
      query = [[ UPDATE applications SET account_id = ?, public_key = ?, secret_key = ?, created_at = ?
                  WHERE id = ?; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM applications WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM applications; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM applications WHERE id = ?; ]]
    },
    __exists = {
      account_id = {
        params = { "account_id" },
        query = [[ SELECT id FROM accounts WHERE id = ?; ]]
      }
    },
    __unique = {
      secret_key = {
        params = { "secret_key" },
        query = [[ SELECT id FROM applications WHERE secret_key = ?; ]]
      }
    }
  }

  Applications.super.new(self, database)
end

function Applications:insert(t)
  -- Determine which statement to use
  if not t.public_key then
    return Applications.super.insert(self, t, self._statements.insert.no_public_key)
  else
    return Applications.super.insert(self, t, self._statements.insert.all)
  end
end

return Applications
