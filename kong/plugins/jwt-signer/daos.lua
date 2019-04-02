local typedefs = require "kong.db.schema.typedefs"

return {
  jwt_signer_jwks = {
    name                = "jwt_signer_jwks",
    primary_key         = { "id" },
    cache_key           = { "name" },
    endpoint_key        = "name",
    generate_admin_api  = false,
    fields = {
      { id = typedefs.uuid },
      {
        name = {
          type= "string",
          required = true,
          unique = true,
        },
      },
      {
        keys = {
          type = "string",
          required = true,
        },
      },
      {
        previous = {
          type = "string",
          required = false,
        },
      },
      { created_at = typedefs.auto_timestamp_s },
      { updated_at = typedefs.auto_timestamp_s },
    },
  },
}
