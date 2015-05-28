local stringy = require "stringy"
local constants = require "kong.constants"

local function check_custom_id_and_username(value, consumer_t)
  local custom_id = consumer_t.custom_id
  local username = consumer_t.username

  if (custom_id == nil or type(custom_id) == "string" and stringy.strip(custom_id) == "")
    and (username == nil or type(username) == "string" and stringy.strip(username) == "") then
      return false, "At least a 'custom_id' or a 'username' must be specified"
  end
  return true
end

return {
  id = { type = constants.DATABASE_TYPES.ID },
  custom_id = { type = "string", unique = true, queryable = true, func = check_custom_id_and_username },
  username = { type = "string", unique = true, queryable = true, func = check_custom_id_and_username },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}
