local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id" },
    key = { type = "string", required = true, unique = true, queryable = true }
  }
}

local KeyAuth = BaseDao:extend()

function KeyAuth:new(properties)
  self._table = "keyauth_credentials"
  self._schema = SCHEMA

  KeyAuth.super.new(self, properties)
end

return { keyauth_credentials = KeyAuth }
