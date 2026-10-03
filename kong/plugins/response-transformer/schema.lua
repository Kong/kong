local typedefs = require "kong.db.schema.typedefs"
local http = require "kong.tools.http"
local validate_header_name = http.validate_header_name
local validate_header_value = http.validate_header_value


local function validate_headers(pair, value_validator)
  local name, value = pair:match("^([^:]+):*(.-)$")
  if validate_header_name(name) == nil then
    return nil, string.format("'%s' is not a valid header", tostring(name))
  end

  if value_validator and value_validator(value) == nil then
    return nil, string.format("'%s' is not a valid header", tostring(value))
  end

  return true
end


local function validate_colon_header_values(pair)
  return validate_headers(pair, validate_header_value)
end


local function validate_colon_headers(pair)
  return validate_headers(pair, validate_header_name)
end

local string_array = {
  type = "array",
  default = {},
  required = true,
  elements = { type = "string" },
}


local colon_string_array = {
  type = "array",
  default = {},
  required = true,
  elements = { type = "string", match = "^[^:]+:.*$" },
}


local string_record = {
  type = "record",
  fields = {
    { json = string_array },
    { headers = string_array },
  },
}


local colon_header_values_array = {
  type = "array",
  default = {},
  required = true,
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_header_values },
}


local colon_string_record = {
  type = "record",
  fields = {
    { json = colon_string_array },
    { json_types = { description = "List of JSON type names. Specify the types of the JSON values returned when appending\nJSON properties. Each string element can be one of: boolean, number, or string.", type = "array",
      default = {},
      required = true,
      elements = {
        type = "string",
        one_of = { "boolean", "number", "string" }
      }
    } },
    { headers = colon_header_values_array },
  },
}

local colon_headers_array = {
  type = "array",
  default = {},
  required = true,
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_headers },
}


local colon_rename_strings_array_record = {
  type = "record",
  fields = {
    { json = colon_string_array },
    { headers = colon_headers_array }
  },
}


return {
  name = "response-transformer",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { remove = string_record },
          { rename  = colon_rename_strings_array_record },
          { replace = colon_string_record },
          { add = colon_string_record },
          { append = colon_string_record },
        },
      },
    },
  },
}
