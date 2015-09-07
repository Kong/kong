local BaseDao = require "kong.dao.cassandra.base_dao"
local crypto = require "kong.plugins.basic-auth.crypto"

local function encrypt_password(password, credential)
  local encrypted, err = crypto.encrypt(credential)
  if err then
    return false, err
  end

  credential.password = encrypted

  return true
end

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", dao_insert_value = true},
    consumer_id = {type = "id", required = true, queryable = true, foreign = "consumers:id"},
    username = {type = "string", required = true, unique = true, queryable = true},
    password = {type = "string", func = encrypt_password}
  }
}

local BasicAuthCredentials = BaseDao:extend()

function BasicAuthCredentials:new(properties)
  self._table = "basicauth_credentials"
  self._schema = SCHEMA

  BasicAuthCredentials.super.new(self, properties)
end

return {basicauth_credentials = BasicAuthCredentials}
