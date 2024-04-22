local typedefs = require "kong.db.schema.typedefs"

return {
  name          = "consumers",
  primary_key   = { "id" },
  endpoint_key  = "username",
  workspaceable = true,

  fields        = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    {
      username = {
        description =
        "The unique username of the Consumer. You must send at least one of username or custom_id with the request.",
        type = "string",
        unique = true
      },
    },
    {
      custom_id =
      {
        description = "Stores the existing unique ID of the consumer. You must send at least one of username or custom_id with the request.",
        type = "string",
        unique = true
      },
    },
    { tags = typedefs.tags },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
