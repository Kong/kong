return {
  name = "mocksocket",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { prefix = { type = "string", match = [[^[%a_][%a%d_]*$]] } },
        },
      },
    },
  },
}
