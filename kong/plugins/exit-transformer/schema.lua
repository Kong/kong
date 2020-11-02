-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME


local function validate_function(fun)
  local func1, err = loadstring(fun)
  if err then
    return false, "Error parsing function: " .. err
  end

  local success, func2 = pcall(func1)

  if not success or func2 == nil then
    -- the code IS the handler function
    return true
  end

  -- the code RETURNED the handler function
  if type(func2) == "function" then
    return true
  end

  -- the code returned something unknown
  return false, "Bad return value from function, expected function type, got "
                .. type(func2)
end


local functions_array = {
  type = "array",
  required = true,
  elements = { type = "string", custom_validator = validate_function }
}


return {
  name = PLUGIN_NAME,
  fields = {
    { config = {
      type = "record",
      fields = {
        { functions = functions_array },
        { handle_unknown = { type = "boolean", default = false } },
        { handle_unexpected = { type = "boolean", default = false } },
      }
    } }
  },
}
