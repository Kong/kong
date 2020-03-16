local typedefs = require "kong.db.schema.typedefs"

return {
  name = "mocking",
  fields = {
    { config = {
      type = "record",
      fields = {
        { api_specification_filename = { type = "string", required = true } },
      }
    } },
  },
}
