local typedefs = require "kong.db.schema.typedefs"

return {
  name = "grpc-web",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
      type = "record",
      fields = {
        {
          proto = {
            type = "string",
            required = false,
            default = nil,
          },
        },
        {
          pass_stripped_path = {
            type = "boolean",
            required = false,
          },
        },
        {
          allow_origin_header = {
            type = "string",
            required = false,
            default = "*",
          },
        },
      },
    }, },
  },
}
