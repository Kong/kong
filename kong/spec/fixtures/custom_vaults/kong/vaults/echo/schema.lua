return {
  name = "echo",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { prefix = { type = "string" } },
          { suffix = { type = "string" } },
        },
      },
    },
  },
}
