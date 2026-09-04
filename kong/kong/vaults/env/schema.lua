return {
  name = "env",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { prefix = { type = "string", match = [[^[%a_-][%a%d_-]*$]], description = "The prefix for the environment variable that the value will be stored in." } },
        },
      },
    },
  },
}
