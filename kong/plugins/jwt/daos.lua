local BaseDao = require "kong.dao.cassandra.base_dao"
local stringy = require "stringy"
local utils = require "kong.tools.utils"

local function generate_secret(v, t, column)
  return true, nil, {[column] = utils.random_string()}
end

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", dao_insert_value = true},
    consumer_id = {type = "id", required = true, queryable = true, foreign = "consumers:id"},
    username = {type = "string", required = true, unique = true, queryable = true},
    secret = {type = "string", unique = true, func = generate_secret}
  }
}

local Jwt = BaseDao:extend()

function Jwt:new(properties)
  self._table = "jwt_secrets"
  self._schema = SCHEMA

  Jwt.super.new(self, properties)
end

return {jwt_secrets = Jwt}
