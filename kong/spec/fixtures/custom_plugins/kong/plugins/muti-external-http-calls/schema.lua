return {
  name = "muti-external-http-calls",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          {
            calls = {
              type = "number",
              required = true,
            },
          }
        },
      },
    },
  },
}
