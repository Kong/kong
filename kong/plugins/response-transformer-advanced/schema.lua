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

  }}}},
}
