return {
  name = "enable-buffering-response",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          {
            phase = {
              type = "string",
              default = "header_filter",
            },
          },
          {
            mode = {
              type = "string",
            },
          },
        },
      },
    },
  },
}
