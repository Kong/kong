local typedefs = require "kong.db.schema.typedefs"


return {
  name = "test",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { default_value     = { type = "string", required = false } },
          { default_value_ttl = { type = "number", required = false } },
          { ttl                 = typedefs.ttl },
          { neg_ttl             = typedefs.ttl },
          { resurrect_ttl       = typedefs.ttl },
        },
      },
    },
  },
}
