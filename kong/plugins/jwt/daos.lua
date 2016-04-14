local utils = require "kong.tools.utils"

local SCHEMA = {
  primary_key = {"id"},
  table = "jwt_secrets",
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, foreign = "consumers:id"},
    key = {type = "string", unique = true, default = utils.random_string},
    secret = {type = "string", unique = true, default = utils.random_string},
    rsa_public_key = {type = "string"},
    algorithm = {type = "string", enum = {"HS256", "RS256"}, default = 'HS256'}
  },
  marshall_event = function(self, t)
    return {id = t.id, consumer_id = t.consumer_id, key = t.key}
  end
}

return {jwt_secrets = SCHEMA}
