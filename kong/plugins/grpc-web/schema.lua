return {
  name = "grpc-web",
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
