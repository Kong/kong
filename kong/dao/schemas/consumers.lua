local utils = require "kong.tools.utils"

local function check_custom_id_and_username(value, consumer_t)
  local username = type(consumer_t.username) == "string" and utils.strip(consumer_t.username) or ""
  local custom_id = type(consumer_t.custom_id) == "string" and utils.strip(consumer_t.custom_id) or ""

  if custom_id == "" and username == "" then
    return false, "At least a 'custom_id' or a 'username' must be specified"
  end

  return true
end

return {
  table = "consumers",
  primary_key = {"id"},
  cache_key = { "id" },
  fields = {
    id = {type = "id", dao_insert_value = true, required = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true, required = true},
    custom_id = {type = "string", unique = true, func = check_custom_id_and_username},
    username = {type = "string", unique = true, func = check_custom_id_and_username}
  },
}
