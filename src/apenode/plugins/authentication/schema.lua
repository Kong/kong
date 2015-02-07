local stringy = require "stringy"
local utils = require "apenode.tools.utils"

local function check_authentication_key_names(names, plugin_value)
  if names and type(names) ~= "table" then
    return false, "You need to specify an array"
  end

  if plugin_value.authentication_type == "basic" or names and utils.table_size(names) > 0 then
    return true
  else
    return false, "You need to specify a query or header name for this authentication type"
  end
end

return {
  authentication_type = { type = "string", required = true, enum = {"query", "basic", "header"} },
  authentication_key_names = { type = "table", required = true, func = check_authentication_key_names },
  hide_credentials = { type = "boolean", default = false }
}