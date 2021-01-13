-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.plugins.response-transformer-advanced.constants"
local validate_function = require "kong.tools.sandbox".validate
local validate_header_name = require("kong.tools.utils").validate_header_name

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


local function validate_headers(pair, validate_value)
  local name, value = pair:match("^([^:]+):*(.-)$")
  if validate_header_name(name) == nil then
    return nil, string.format("'%s' is not a valid header", tostring(name))
  end

  if validate_value then
    if validate_header_name(value) == nil then
      return nil, string.format("'%s' is not a valid header", tostring(value))
    end
  end
  return true
end

local function validate_colon_headers(pair)
  return validate_headers(pair, true)
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


local colon_headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_headers },
}


local json_types_array = {
  type = "array",
  default = {},
  elements = {
    type = "string",
    one_of = { "boolean", "number", "string" }
  }
}


return {
  name = "response-transformer-advanced",
  fields = {
    { config = { type = "record", fields = {
      { remove = { type = "record", fields = {
        { json = strings_array },
        { headers = strings_array },
        { if_status = status_array },
      }}},
      { rename = { type = "record", fields = {
        { headers = colon_headers_array },
        { if_status = status_array }
      }}
      },
      { replace = { type = "record", fields = {
          { body = { type = "string" } },
          { json = colon_strings_array },
          { json_types = json_types_array },
          { headers = colon_strings_array },
          { if_status = status_array },
      }}},
      { add = { type = "record", fields = {
          { json = colon_strings_array },
          { json_types = json_types_array },
          { headers = colon_strings_array },
          { if_status = status_array },
      }}},
      { append = { type = "record", fields = {
          { json = colon_strings_array },
          { json_types = json_types_array },
          { headers = colon_strings_array },
          { if_status = status_array },
      }}},
      { allow  = {
        type = "record",
        fields = {
          { json = strings_set },
      }}},
      { transform = { type = "record", fields = {
          { functions = functions_array },
          { if_status = status_array },
          { json = strings_array },
      }}},
      { dots_in_keys = { type = "boolean", default = false }, },
  },
  shorthands = {
    -- deprecated forms, to be removed in Kong EE 3.x
    { whitelist = function(value)
        return { allow = value }
      end },
  }}}},
}
