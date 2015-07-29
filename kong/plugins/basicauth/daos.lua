local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id" },
    username = { type = "string", required = true, unique = true, queryable = true },
    password = { type = "string" }
  }
}

local BasicAuthCredentials = BaseDao:extend()

function BasicAuthCredentials:new(properties)
  self._table = "basicauth_credentials"
  self._schema = SCHEMA

  BasicAuthCredentials.super.new(self, properties)
end

return { basicauth_credentials = BasicAuthCredentials }
