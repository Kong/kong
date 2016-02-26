local utils = require "kong.tools.utils"
local stringy = require "stringy"

local function generate_if_missing(v, t, column)
  if not v or stringy.strip(v) == "" then
    return true, nil, {[column] = utils.random_string()}
  end
  return true
end

local SCHEMA = {
  primary_key = {"id"},
  table = "keyauth_credentials",
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, foreign = "consumers:id"},
    key = {type = "string", required = false, unique = true, func = generate_if_missing}
  },
  marshall_event = function(self, t)
    return {id = t.id, consumer_id = t.consumer_id, key = t.key}
  end
}

return {keyauth_credentials = SCHEMA}
