local stringy = require "stringy"
local utils = require "kong.tools.utils"

local BASIC = "basic"

local function check_authentication_key_names(names, plugin_value)
  if names and type(names) ~= "table" then
    return false, "You need to specify an array"
  end

  if plugin_value.authentication_type == BASIC or (names and utils.table_size(names) > 0) then
    return true
  else
    return false, "This field is not available for \""..BASIC.."\" authentication"
  end
end

return {
  authentication_type = { type = "string", required = true, enum = {"query", BASIC, "header"} },
  authentication_key_names = { type = "table", func = check_authentication_key_names },
  hide_credentials = { type = "boolean", default = false }
}
