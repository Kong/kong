local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME

local match = ngx.re.match

local constants = {
  REGEX_SPLIT_RANGE  = "(\\d\\d\\d)-(\\d\\d\\d)",
  REGEX_SINGLE_STATUS_CODE  = "^\\d\\d\\d$"
}

-- checks if status code entries follow status code or status code range pattern (xxx or xxx-xxx)
local function validate_status(entry)
  local single_code = match(entry, constants.REGEX_SINGLE_STATUS_CODE)
  local range = match(entry, constants.REGEX_SPLIT_RANGE)

  if not single_code and not range then
    return false, "value '" .. entry .. "' is neither status code nor status code range"
  end
  return true
end


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


local status_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = validate_status },
}


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
        { if_status = status_array },
      }
    } }
  },
}
