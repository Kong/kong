local typedefs = require "kong.db.schema.typedefs"
local is_regex = require("kong.db.schema").validators.is_regex


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
    { run_on = typedefs.run_on_first },
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
              elements = {
                type = "string",
                one_of = { "HEAD", "GET", "POST", "PUT", "PATCH", "DELETE" },
          }, }, },
          { max_age = { type = "number" }, },
          { credentials = { type = "boolean", default = false }, },
          { preflight_continue = { type = "boolean", default = false }, },
    }, }, },
  },
}

