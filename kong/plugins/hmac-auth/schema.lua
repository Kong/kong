local utils = require "kong.tools.utils"

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end
  
  return false, "the anonymous user must be empty or a valid uuid"
end

local function check_clock_skew_positive(v)
  if v and v < 0 then
    return false, "Clock Skew should be positive"
  end
  return true
end

return {
  no_consumer = true,
  fields = {
    hide_credentials = { type = "boolean", default = false },
    clock_skew = { type = "number", default = 300, func = check_clock_skew_positive },
    anonymous = {type = "string", default = "", func = check_user},
  }
}
