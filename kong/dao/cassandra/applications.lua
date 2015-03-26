local BaseDao = require "kong.dao.cassandra.base_dao"
local constants = require "kong.constants"

local SCHEMA = {
  id = { type = constants.DATABASE_TYPES.ID },
  consumer_id = { type = constants.DATABASE_TYPES.ID, required = true, foreign = true, queryable = true },
  public_key = { type = "string", required = true, unique = true, queryable = true },
  secret_key = { type = "string" },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local Applications = BaseDao:extend()

function Applications:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "consumer_id", "public_key", "secret_key", "created_at" },
      query = [[
        INSERT INTO applications(id, consumer_id, public_key, secret_key, created_at)
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
      consumer_id = {
        params = { "consumer_id" },
        query = [[ SELECT id FROM consumers WHERE id = ?; ]]
      }
    },
    __unique = {
      public_key = {
        params = { "public_key" },
        query = [[ SELECT id FROM applications WHERE public_key = ?; ]]
      }
    }
  }

  Applications.super.new(self, properties)
end

return Applications
