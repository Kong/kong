return {
  name = "invalid-schema",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { foo = { type = "bar" } },
        },
      },
    },
  },
}
