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
            required = true,
            default = nil,
          },
        },
        {
          additional_protos = {
            type = "array",
            required = false,
            default = nil,
            elements = {
              type = "string",
            },
          },
        },
        {
          use_proto_names = {
            type = "boolean",
            required = false,
            default = false,
          },
        },
        {
          enum_as_name = {
            type = "boolean",
            required = false,
            default = true,
          },
        },
        {
          emit_defaults = {
            type = "boolean",
            required = false,
            default = false,
          },
        },
      },
    }, },
  },
}
