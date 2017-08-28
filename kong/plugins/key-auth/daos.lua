local utils = require "kong.tools.utils"

local SCHEMA = {
  primary_key = {"id"},
  table = "keyauth_credentials",
  cache_key = { "key" },
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, foreign = "consumers:id"},
    key = {type = "string", required = false, unique = true, default = utils.random_string}
  },
}

return {keyauth_credentials = SCHEMA}
