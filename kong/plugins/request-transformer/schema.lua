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


local strings_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}


local headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = validate_headers },
}


local strings_array_record = {
  type = "record",
  fields = {
    { body = strings_array },
    { headers = headers_array },
    { querystring = strings_array },
  },
}


local colon_strings_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$" },
}

local colon_headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_headers },
}


local colon_header_value_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_headers },
}


local colon_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_header_value_array },
    { querystring = colon_strings_array },
  },
}


local colon_rename_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_headers_array },
    { querystring = colon_strings_array },
  },
}


return {
  name = "request-transformer",
  fields = {
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { http_method = typedefs.http_method },
          { remove  = strings_array_record },
          { rename  = colon_rename_strings_array_record },
          { replace = colon_strings_array_record },
          { add     = colon_strings_array_record },
          { append  = colon_strings_array_record },
        }
      },
    },
  }
}
