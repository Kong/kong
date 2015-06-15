local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id", queryable = true },
    username = { type = "string", required = true, unique = true, queryable = true },
    password = { type = "string" }
  }
}

local BasicAuthCredentials = BaseDao:extend()

function BasicAuthCredentials:new(properties)
  self._table = "basicauth_credentials"
  self._schema = SCHEMA
  self._primary_key = {"id"}
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
    },
    drop = "TRUNCATE basicauth_credentials;"
  }

  BasicAuthCredentials.super.new(self, properties)
end

return { basicauth_credentials = BasicAuthCredentials }
