local BaseDao = require "kong.dao.cassandra.base_dao"
local utils = require "kong.tools.utils"

local SCHEMA = {
  primary_key = {"id"},
  table = "jwt_secrets",
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

function Jwt:new(...)
  Jwt.super.new(self, SCHEMA, ...)
end

return {jwt_secrets = Jwt}
