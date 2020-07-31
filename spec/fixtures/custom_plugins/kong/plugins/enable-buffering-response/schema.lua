return {
  name = "enable-buffering",
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
