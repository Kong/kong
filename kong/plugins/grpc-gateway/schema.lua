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
            description = "Describes the gRPC types and methods.\n[HTTP configuration](https://github.com/googleapis/googleapis/blob/fc37c47e70b83c1cc5cc1616c9a307c4303fe789/google/api/http.proto)\nmust be defined in the file.",
            type = "string",
            required = false,
            default = nil,
          },
        },
      },
    }, },
  },
}
