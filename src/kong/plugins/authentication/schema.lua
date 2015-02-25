local constants = require "kong.constants"
local utils = require "kong.tools.utils"
local stringy = require "stringy"

local function check_authentication_key_names(names, plugin_value)
  if plugin_value.authentication_type == constants.AUTHENTICATION.BASIC and names then
    return false, "This field is not available for \""..constants.AUTHENTICATION.BASIC.."\" authentication"
  elseif plugin_value.authentication_type ~= constants.AUTHENTICATION.BASIC then
    if names then
      if type(names) == "table" and utils.table_size(names) > 0 then
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
  authentication_type = { required = true, immutable = true, enum = { constants.AUTHENTICATION.QUERY,
                                                                      constants.AUTHENTICATION.BASIC,
                                                                      constants.AUTHENTICATION.HEADER }},
  authentication_key_names = { type = "table", func = check_authentication_key_names },
  hide_credentials = { type = "boolean", default = false }
}
