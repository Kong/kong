local typedefs = require "kong.db.schema.typedefs"
local validate_header_name = require("kong.tools.utils").validate_header_name


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

local string_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}


local colon_string_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$" },
}


local string_record = {
  type = "record",
  fields = {
    { json = string_array },
    { headers = string_array },
  },
}


local colon_string_record = {
  type = "record",
  fields = {
    { json = colon_string_array },
    { json_types = {
      type = "array",
      default = {},
      elements = {
        type = "string",
        one_of = { "boolean", "number", "string" }
      }
    } },
    { headers = colon_string_array },
  },
}

local colon_headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_headers },
}


local colon_rename_strings_array_record = {
  type = "record",
  fields = {
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
