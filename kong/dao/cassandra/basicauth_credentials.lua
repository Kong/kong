local BaseDao = require "kong.dao.cassandra.base_dao"
local constants = require "kong.constants"

local SCHEMA = {
  id = { type = constants.DATABASE_TYPES.ID },
  consumer_id = { type = constants.DATABASE_TYPES.ID, required = true, foreign = true, queryable = true },
  username = { type = "string", required = true, unique = true, queryable = true },
  password = { type = "string" },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local BasicAuthCredentials = BaseDao:extend()

function BasicAuthCredentials:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      args_keys = { "id", "consumer_id", "username", "password", "created_at" },
      query = [[
        INSERT INTO basicauth_credentials(id, consumer_id, username, password, created_at)
          VALUES(?, ?, ?, ?, ?);
      ]]
    },
    update = {
      args_keys = { "username", "password", "created_at", "id" },
      query = [[ UPDATE basicauth_credentials SET username = ?, password = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM basicauth_credentials %s; ]]
    },
    select_one = {
      args_keys = { "id" },
      query = [[ SELECT * FROM basicauth_credentials WHERE id = ?; ]]
    },
    delete = {
      args_keys = { "id" },
      query = [[ DELETE FROM basicauth_credentials WHERE id = ?; ]]
    },
    __foreign = {
      consumer_id = {
        args_keys = { "consumer_id" },
        query = [[ SELECT id FROM consumers WHERE id = ?; ]]
      }
    },
    __unique = {
      username = {
        args_keys = { "username" },
        query = [[ SELECT id FROM basicauth_credentials WHERE username = ?; ]]
      }
    }
  }

  BasicAuthCredentials.super.new(self, properties)
end

return BasicAuthCredentials
