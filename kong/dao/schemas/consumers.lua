local stringy = require "stringy"

local function check_custom_id_and_username(value, consumer_t)
  local username = type(consumer_t.username) == "string" and stringy.strip(consumer_t.username) or ""
  local custom_id = type(consumer_t.custom_id) == "string" and stringy.strip(consumer_t.custom_id) or ""

  if custom_id == "" and username == "" then
    return false, "At least a 'custom_id' or a 'username' must be specified"
  end

  return true
end

return {
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    custom_id = { type = "string", unique = true, func = check_custom_id_and_username },
    username = { type = "string", unique = true, func = check_custom_id_and_username }
  }
}
