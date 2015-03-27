local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  key = { type = "string", required = true, queryable = true },
  consumer_id = { type = constants.DATABASE_TYPES.ID,
                  required = true,
                  foreign = true,
                  immutable = true },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local KeyAuthDAO = BaseDao:extend()

function KeyAuthDAO:new(properties)
  self._entity = "keyauth_credentials"
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "key", "consumer_id", "created_at" },
      query = [[ INSERT INTO keyauth_credentials(key, consumer_id, created_at) VALUES(?, ?, ?); ]]
    },
    select = {
      query = [[ SELECT * FROM keyauth_credentials %s; ]]
    },
    select_one = {
      params = { "key" },
      query = [[ SELECT * FROM keyauth_credentials WHERE key = ?; ]]
    },
    delete = {
      params = { "key" },
      query = [[ DELETE FROM keyauth_credentials WHERE key = ?; ]]
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
        query = [[ SELECT * FROM keyauth_credentials WHERE key = ?; ]]
      }
    }
  }

  KeyAuthDAO.super.new(self, properties)
end

return KeyAuthDAO
