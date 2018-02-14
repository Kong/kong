local singletons = require "kong.singletons"
local crypto = require "kong.plugins.basic-auth.crypto"

local function encrypt_password(password, credential)
  -- Don't re-encrypt the password digest on update, if the password hasn't changed
  -- This causes a bug when a new password is effectively equal the to previous digest
  -- TODO: Better handle this scenario
  if credential.id and singletons.dao then
    local result = singletons.dao.basicauth_credentials:find {id = credential.id}
    if result and result.password == credential.password then
      return true
    end
  end

  credential.password = crypto.encrypt(credential)
  return true
end

local SCHEMA = {
  primary_key = {"id"},
  table = "basicauth_credentials",
  cache_key = { "username" },
  workspaceable = true,
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, foreign = "consumers:id"},
    username = {type = "string", required = true, unique = true },
    password = {type = "string", func = encrypt_password}
  },
}

return {basicauth_credentials = SCHEMA}
