local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  id = { type = "id", dao_insert_value = true },
  created_at = { type = "timestamp", dao_insert_value = true },
  consumer_id = { type = "id", required = true, foreign = true, queryable = true },
  key = { type = "string", required = true, unique = true, queryable = true }
}

local KeyAuth = BaseDao:extend()

function KeyAuth:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      args_keys = { "id", "consumer_id", "key", "created_at" },
      query = [[
        INSERT INTO keyauth_credentials(id, consumer_id, key, created_at)
          VALUES(?, ?, ?, ?);
      ]]
    },
    update = {
      args_keys = { "key", "created_at", "id" },
      query = [[ UPDATE keyauth_credentials SET key = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM keyauth_credentials %s; ]]
    },
    select_one = {
      args_keys = { "id" },
      query = [[ SELECT * FROM keyauth_credentials WHERE id = ?; ]]
    },
    delete = {
      args_keys = { "id" },
      query = [[ DELETE FROM keyauth_credentials WHERE id = ?; ]]
    },
    __foreign = {
      consumer_id = {
        args_keys = { "consumer_id" },
        query = [[ SELECT id FROM consumers WHERE id = ?; ]]
      }
    },
    __unique = {
      key = {
        args_keys = { "key" },
        query = [[ SELECT id FROM keyauth_credentials WHERE key = ?; ]]
      }
    },
    drop = "TRUNCATE keyauth_credentials;"
  }

  KeyAuth.super.new(self, properties)
end

return { keyauth_credentials = KeyAuth }
