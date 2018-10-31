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
    password = {type = "string"},
    rounds = {type = "number", default = 7, immutable = true}
  },
  self_check = function(schema, credential, dao, is_updating)
    -- if it doesnt look like a bcrypt digest, Do The Thing
    if credential.password and not string.find(credential.password, "^%$2b%$") then
      local bcrypt = require "bcrypt"

      local digest = bcrypt.digest(credential.password, credential.rounds)

      credential.password = digest
    end
  end,
}

return {basicauth_credentials = SCHEMA}
