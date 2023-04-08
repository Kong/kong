local typedefs = require "kong.db.schema.typedefs"

return {
  name           = "key_sets",
  dao            = "kong.db.dao.key_sets",
  primary_key    = { "id" },
  endpoint_key   = "name",
  admin_api_name = "key-sets",
  workspaceable  = true,
  ttl            = false,
  fields         = {
    {
      id = typedefs.uuid,
    },
    {
      name = {
        type     = "string",
        required = false,
        unique   = true,
        indexed  = true,
      },
    },
    {
      tags = typedefs.tags,
    },
    {
      created_at = typedefs.auto_timestamp_s,
    },
    {
      updated_at = typedefs.auto_timestamp_s,
    },
  },
}
