local utils = require "kong.tools.utils"

local SCHEMA = {
  primary_key = {"id"},
  table = "hmacauth_credentials",
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, foreign = "consumers:id"},
    username = {type = "string", required = true, unique = true},
    secret = {type = "string", default = utils.random_string}
  },
  marshall_event = function(self, t)
    return {id = t.id, consumer_id = t.consumer_id, username = t.username}
  end
}

return {hmacauth_credentials = SCHEMA}
