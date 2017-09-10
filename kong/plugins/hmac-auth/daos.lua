local utils = require "kong.tools.utils"

local SCHEMA = {
  primary_key = {"id"},
  table = "hmacauth_credentials",
  cache_key = { "username" },
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, foreign = "consumers:id"},
    username = {type = "string", required = true, unique = true},
    secret = {type = "string", default = utils.random_string}
  },
}

return {hmacauth_credentials = SCHEMA}
