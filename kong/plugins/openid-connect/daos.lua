local typedefs = require "kong.db.schema.typedefs"


return {
  oic_issuers = {
    name               = "oic_issuers",
    primary_key        = { "id" },
    cache_key          = { "issuer" },
    endpoint_key       = "issuer",
    generate_admin_api = false,
    fields = {
      {
        id = typedefs.uuid,
      },
      {
        issuer = typedefs.url {
          required = true,
          unique   = true,
        },
      },
      {
        configuration = {
          required = true,
          type     = "string",
        },
      },
      {
        keys = {
          required = true,
          type     = "string",
        },
      },
      {
        secret = {
          required = true,
          type     = "string",
        },
      },
      {
        created_at = typedefs.auto_timestamp_s,
      },
    },
  },
}
