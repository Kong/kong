local typedefs = require "kong.db.schema.typedefs"

return {
  name = "grpc-gateway",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
      type = "record",
      fields = {
        {
          proto = {
            description = "Describes the gRPC types and methods.",
            type = "string",
            required = false,
            default = nil,
          },
        },
      },
    }, },
  },
}
