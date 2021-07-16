local typedefs = require "kong.db.schema.typedefs"

return {
  name = "hybrid-comm-tests",
  fields = {
    {
      protocols = typedefs.protocols,
    },
    {
      config = {
        type = "record",
        fields = {},
      },
    },
  },
}
