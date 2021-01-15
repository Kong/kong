return {
  name = "grpc-gateway",
  fields = {
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
      },
    }, },
  },
}
