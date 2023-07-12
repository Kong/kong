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
          { origins = { description = "List of allowed domains for the `Access-Control-Allow-Origin` header. If you want to allow all origins, add `*` as a single value to this configuration field. The accepted values can either be flat strings or PCRE regexes.", type = "array",
              elements = {
                type = "string",
                custom_validator = validate_asterisk_or_regex,
          }, }, },
          { headers = { description = "Value for the `Access-Control-Allow-Headers` header.", type = "array", elements = { type = "string" }, }, },
          { exposed_headers = { description = "Value for the `Access-Control-Expose-Headers` header. If not specified, no custom headers are exposed.", type = "array", elements = { type = "string" }, }, },
          { methods =  { description = "'Value for the `Access-Control-Allow-Methods` header. Available options include `GET`, `HEAD`, `PUT`, `PATCH`, `POST`, `DELETE`, `OPTIONS`, `TRACE`, `CONNECT`. By default, all options are allowed.'", type = "array",
              default = METHODS,
              elements = {
                type = "string",
                one_of = METHODS,
          }, }, },
          { max_age = { description = "Indicates how long the results of the preflight request can be cached, in `seconds`.", type = "number" }, },
          { credentials = { description = "Flag to determine whether the `Access-Control-Allow-Credentials` header should be sent with `true` as the value.", type = "boolean", required = true, default = false }, },
          { preflight_continue = { description = "A boolean value that instructs the plugin to proxy the `OPTIONS` preflight request to the Upstream service.", type = "boolean", required = true, default = false }, },
    }, }, },
  },
}
