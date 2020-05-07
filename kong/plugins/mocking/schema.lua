return {
  name = "mocking",
  fields = {
    { config = {
      type = "record",
      fields = {
        { api_specification_filename = { type = "string", required = true } },
        { random_delay = { type = "boolean", default = false } },
        { max_delay_time = { type = "integer", default = 5 } },
      }
    } },
  },
}
