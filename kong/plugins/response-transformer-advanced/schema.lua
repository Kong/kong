local typedefs = require "kong.db.schema.typedefs"
local constants = require "kong.plugins.response-transformer-advanced.constants"

local match = ngx.re.match


-- entries must have colons to set the key and value apart
local function check_for_value(entry)
  if not match(entry, "^[^:]+:.*$") then
    return false, "key '" .. entry .. "' has no value"
  end
  return true
end


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
  local func1, err = load(fun)
  if err then
    return false, "Error parsing function: " .. err
  end

  setfenv(func1, {})
  local success, func2 = pcall(func1)

  -- the code RETURNED the handler function
  if success and type(func2) == "function" then
    return true
  end

  -- the code returned something unknown
  return false, "Bad return value from function, expected function type, got "
                .. type(func2)
end


local strings_array = {
  type = "array",
  default = {},
  elements = { type = "string" }
}


local colon_strings_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = check_for_value },
}


local status_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = validate_status },
}

local functions_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = validate_function }
}


local strings_set = {
  type = "set",
  elements = { type = "string" },
}


return {
  name = "response-transformer-advanced",
  fields = {
    { run_on = typedefs.run_on_first },
    { config = { type = "record", fields = {
      { remove = { type = "record", fields = {
        { json = strings_array },
        { headers = strings_array },
        { if_status = status_array },
      }}},
      { replace = { type = "record", fields = {
          { body = { type = "string" } },
          { json = colon_strings_array },
          { headers = colon_strings_array },
          { if_status = status_array },
      }}},
      { add = { type = "record", fields = {
          { json = colon_strings_array },
          { headers = colon_strings_array },
          { if_status = status_array },
      }}},
      { append = { type = "record", fields = {
          { json = colon_strings_array },
          { headers = colon_strings_array },
          { if_status = status_array },
      }}},
      { whitelist  = {
        type = "record",
        fields = {
          { json = strings_set },
      }}},
      { transform = { type = "record", fields = {
          { functions = functions_array },
          { if_status = status_array },
      }}},
  }}}},
}
