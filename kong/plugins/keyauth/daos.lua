local utils = require "kong.tools.utils"
local stringy = require "stringy"
local BaseDao = require "kong.dao.cassandra.base_dao"

local function generate_if_missing(v, t, column)
  if not v or stringy.strip(v) == "" then
    return true, nil, { [column] = utils.random_string()}
  end
  return true
end

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id" },
    key = { type = "string", required = false, unique = true, queryable = true, func = generate_if_missing }
  }
}

local KeyAuth = BaseDao:extend()

function KeyAuth:new(properties)
  self._table = "keyauth_credentials"
  self._schema = SCHEMA

  KeyAuth.super.new(self, properties)
end

return { keyauth_credentials = KeyAuth }
