local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true },
    consumer_id = { type = "id", required = true, queryable = true, foreign = "consumers:id" },
    username = { type = "string", required = true, unique = true, queryable = true },
    secret = { type = "string" }
  },
  marshall_event = function(self, t)
    return { id = t.id, consumer_id = t.consumer_id, username = t.username }
  end
}

local HMACAuthCredentials = BaseDao:extend()

function HMACAuthCredentials:new(properties, events_handler)
  self._table = "hmacauth_credentials"
  self._schema = SCHEMA
  HMACAuthCredentials.super.new(self, properties, events_handler)
end

return { hmacauth_credentials = HMACAuthCredentials }
