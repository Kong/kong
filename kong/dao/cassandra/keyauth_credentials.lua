local BaseDao = require "kong.dao.cassandra.base_dao"
local constants = require "kong.constants"

local SCHEMA = {
  id = { type = constants.DATABASE_TYPES.ID },
  consumer_id = { type = constants.DATABASE_TYPES.ID, required = true, foreign = true, queryable = true },
  key = { type = "string", required = true, unique = true, queryable = true },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local KeyAuthCredentials = BaseDao:extend()

function KeyAuthCredentials:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "consumer_id", "key", "created_at" },
      query = [[
        INSERT INTO keyauth_credentials(id, consumer_id, key, created_at)
          VALUES(?, ?, ?, ?);
      ]]
    },
    update = {
      params = { "key", "created_at", "id" },
      query = [[ UPDATE keyauth_credentials SET key = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM keyauth_credentials %s; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM keyauth_credentials WHERE id = ?; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM keyauth_credentials WHERE id = ?; ]]
    },
    __foreign = {
      consumer_id = {
        params = { "consumer_id" },
        query = [[ SELECT id FROM consumers WHERE id = ?; ]]
      }
    },
    __unique = {
      key = {
        params = { "key" },
        query = [[ SELECT id FROM keyauth_credentials WHERE key = ?; ]]
      }
    }
  }

  KeyAuthCredentials.super.new(self, properties)
end

return KeyAuthCredentials
