return {
  name = "grpc-gatewat",
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