return {
  name = "request-size-limiting",
  fields = {
    { config = {
        type = "record",
        fields = {
          { allowed_payload_size = { type = "integer", default = 128 }, },
        },
      },
    },
  },
}
