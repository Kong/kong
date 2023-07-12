return {
  name = "test",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { default_value     = { type = "string", required = false } },
          { default_value_ttl = { type = "number", required = false } },
        },
      },
    },
  },
}
