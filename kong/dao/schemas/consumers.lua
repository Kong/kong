local stringy = require "stringy"
local constants = require "kong.constants"

local function check_custom_id_and_username(value, consumer_t)
  if (consumer_t.custom_id == nil or stringy.strip(consumer_t.custom_id) == "")
    and (consumer_t.username == nil or stringy.strip(consumer_t.username) == "") then
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
