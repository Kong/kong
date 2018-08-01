local typedefs = require "kong.db.schema.typedefs"

return {
  name = "apis",
  legacy = true,
  primary_key  = { "id" },
  endpoint_key = "name",

  fields = {
    { id = typedefs.uuid, },
    { name = { type = "string", unique = true } },
  },
}
