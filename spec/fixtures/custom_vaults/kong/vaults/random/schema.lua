local typedefs = require "kong.db.schema.typedefs"

return {
  name = "random",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { prefix = { type = "string" } },
          { suffix = { type = "string" } },
          { ttl           = typedefs.ttl },
          { neg_ttl       = typedefs.ttl },
          { resurrect_ttl = typedefs.ttl },
        },
      },
    },
  },
}
