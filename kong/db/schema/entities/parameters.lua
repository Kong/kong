local typedefs = require "kong.db.schema.typedefs"

return {
  name               = "parameters",
  primary_key        = { "key", },
  workspaceable      = false,
  generate_admin_api = false,
  cache_key          = { "key" },

  fields = {
    { created_at     = typedefs.auto_timestamp_s },
    { key            = { description = "They key value of a parameter.", type = "string", required = true, unique = true, }, },
    { value          = { description = "The value attached to the key.", type = "string", required = true, }, },
  },
}
