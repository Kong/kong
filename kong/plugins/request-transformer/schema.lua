local typedefs = require "kong.db.schema.typedefs"


local strings_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}


local strings_array_record = {
  type = "record",
  fields = {
    { body = strings_array },
    { headers = strings_array },
    { querystring = strings_array },
  },
}


local colon_strings_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$" },
}


local colon_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_strings_array },
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
          { rename  = colon_strings_array_record },
          { replace = colon_strings_array_record },
          { add     = colon_strings_array_record },
          { append  = colon_strings_array_record },
        }
      },
    },
  }
}
