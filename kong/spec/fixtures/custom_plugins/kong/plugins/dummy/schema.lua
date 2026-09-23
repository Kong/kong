local typedefs = require "kong.db.schema.typedefs"

return {
  name = "dummy",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { resp_header_value = { type = "string", default = "1", referenceable = true } },
          { resp_headers = {
            type   = "map",
            keys   = typedefs.header_name,
            values = {
              type          = "string",
              referenceable = true,
            }
          }},
          { append_body = { type = "string" } },
          { resp_code = { type = "number" } },
          { test_try = { type = "boolean", default = false}},
          { old_field = {
              type = "number",
              deprecation = {
                message = "dummy: old_field is deprecated",
                removal_in_version = "x.y.z",
                old_default = 42 }, }, }
        },
      },
    },
  },
}
