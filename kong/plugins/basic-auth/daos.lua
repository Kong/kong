local BaseDao = require "kong.dao.cassandra.base_dao"
local crypto = require "kong.plugins.basic-auth.crypto"

local function encrypt_password(password, credential)
  -- Don't re-encrypt the password digest on update, if the password hasn't changed
  -- This causes a bug when a new password is effectively equal the to previous digest
  -- TODO: Better handle this scenario
  if credential.id then
    if dao then -- Check to make this work with tests
      local result = dao.basicauth_credentials:find_by_primary_key({id=credential.id})
      if result and result.password == credential.password then
        return true
      end
    end
  end

  credential.password = crypto.encrypt(credential)
  return true
end

local SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, queryable = true, foreign = "consumers:id"},
    username = {type = "string", required = true, unique = true, queryable = true},
    password = {type = "string", func = encrypt_password}
  },
  marshall_event = function(self, t)
    return { id = t.id, consumer_id = t.consumer_id, username = t.username }
  end
}

local BasicAuthCredentials = BaseDao:extend()

function BasicAuthCredentials:new(properties, events_handler)
  self._table = "basicauth_credentials"
  self._schema = SCHEMA

  BasicAuthCredentials.super.new(self, properties, events_handler)
end

return {basicauth_credentials = BasicAuthCredentials}
