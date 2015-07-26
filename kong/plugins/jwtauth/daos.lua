local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id" },
    secret = { type = "string", required = true, unique = true, queryable = true },
    secret_is_base64_encoded = { type = "boolean", required = true, default = false }
  }
}

local JwtAuth = BaseDao:extend()

function JwtAuth:new(properties)
  self._table = "jwtauth_credentials"
  self._schema = SCHEMA

  JwtAuth.super.new(self, properties)
end

return { jwtauth_credentials = JwtAuth }
