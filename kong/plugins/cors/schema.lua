local typedefs = require "kong.db.schema.typedefs"
local is_regex = require("kong.db.schema").validators.is_regex


local METHODS = {
  "GET",
  "HEAD",
  "PUT",
  "PATCH",
  "POST",
  "DELETE",
  "OPTIONS",
  "TRACE",
  "CONNECT",
}


local function validate_asterisk_or_regex(value)
  if value == "*" or is_regex(value) then
    return true
  end
  return nil, string.format("'%s' is not a valid regex", tostring(value))
end


return {
  name = "cors",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { origins = {
              type = "array",
              elements = {
                type = "string",
                custom_validator = validate_asterisk_or_regex,
          }, }, },
          { headers = { type = "array", elements = { type = "string" }, }, },
          { exposed_headers = { type = "array", elements = { type = "string" }, }, },
          { methods = {
              type = "array",
              default = METHODS,
              elements = {
                type = "string",
                one_of = METHODS,
          }, }, },
          { max_age = { type = "number" }, },
          { credentials = { type = "boolean", default = false }, },
          { preflight_continue = { type = "boolean", default = false }, },
    }, }, },
  },
}

