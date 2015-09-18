local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true, queryable = true, foreign = "consumers:id" },
    username = { type = "string", required = true, unique = true, queryable = true },
    secret = { type = "string" }
  }
}

local HMACAuthCredentials = BaseDao:extend()

function HMACAuthCredentials:new(properties)
  self._table = "hmacauth_credentials"
  self._schema = SCHEMA
  HMACAuthCredentials.super.new(self, properties)
end

return { hmacauth_credentials = HMACAuthCredentials }
