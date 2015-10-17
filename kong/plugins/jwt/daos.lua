local BaseDao = require "kong.dao.cassandra.base_dao"
local utils = require "kong.tools.utils"

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, queryable = true, foreign = "consumers:id"},
    key = {type = "string", unique = true, queryable = true, default = utils.random_string},
    secret = {type = "string", unique = true, default = utils.random_string}
  },
  marshall_event = function(self, t)
    return { id = t.id, consumer_id = t.consumer_id, key = t.key }
  end
}

local Jwt = BaseDao:extend()

function Jwt:new(properties, events_handler)
  self._table = "jwt_secrets"
  self._schema = SCHEMA

  Jwt.super.new(self, properties, events_handler)
end

return {jwt_secrets = Jwt}
