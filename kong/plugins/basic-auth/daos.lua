local BaseDao = require "kong.dao.cassandra.base_dao"
local crypto = require "kong.plugins.basic-auth.crypto"
local utils = require "kong.tools.utils" 

local function encrypt_password(password, credential)
  credential.password = crypto.encrypt(credential)
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

function BasicAuthCredentials:insert(params)
  if params.password then
    return BasicAuthCredentials.super.insert(self, params)
  else
    -- No password was provided, so we insert a random generated password
    local newpwd = utils.random_string()
    params.password = newpwd
    local data, err = BasicAuthCredentials.super.insert(self, params)
    -- inserting the data has encrypted the password field by now, 
    -- so add a new field with the generated plain text password
    -- which will be returned to the requester
    data.plain_password = newpwd
    return data, err
  end
end

return {basicauth_credentials = BasicAuthCredentials}
