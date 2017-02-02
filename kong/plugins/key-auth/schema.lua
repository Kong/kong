local utils = require "kong.tools.utils"

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end
  
  return false, "the anonymous user must be empty or a valid uuid"
end

local function default_key_names(t)
  if not t.key_names then
    return {"apikey"}
  end
end

return {
  no_consumer = true,
  fields = {
    key_names = {required = true, type = "array", default = default_key_names},
    hide_credentials = {type = "boolean", default = false},
    anonymous = {type = "string", default = "", func = check_user},
  }
}
