local stringy = require "stringy"
local utils = require "kong.tools.utils"

local BASIC = "basic"

local function check_authentication_key_names(names, plugin_value)
  if plugin_value.authentication_type == BASIC then
    return false, "This field is not available for \""..BASIC.."\" authentication"
  elseif plugin_value.authentication_type ~= BASIC then
    if names then
      if type(names) == "table" then
        return true
      else
        return false, "You need to specify an array"
      end
    else
      return false, "This field is required for query and header authentication"
    end
  end
end

return {
  authentication_type = { required = true, enum = { "query", BASIC, "header" }, immutable = true },
  authentication_key_names = { type = "table", func = check_authentication_key_names },
  hide_credentials = { type = "boolean", default = false }
}
