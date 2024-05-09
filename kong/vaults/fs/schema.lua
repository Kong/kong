return {
  name = "fs",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          {
            prefix = {
              type = "string",
              match = [[^[^*&%%\`]+$]],
              required = true,
              description = "The prefix path for the file vault referenced files."
            },
          },
        },
      },
    },
  },
}
