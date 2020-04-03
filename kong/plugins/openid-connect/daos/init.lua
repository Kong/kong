local typedefs = require "kong.db.schema.typedefs"
local oidcdefs = require "kong.plugins.openid-connect.typedefs"


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
  oic_jwks = {
    name               = "oic_jwks",
    dao                = "kong.plugins.openid-connect.daos.jwks",
    primary_key        = { "id" },
    generate_admin_api = false,
    fields = {
      {
        id = {
          type = "string",
          uuid    = true,
          auto    = false,
          default = "c3cfba2d-1617-453f-a416-52e6edb5f9a0",
          eq      = "c3cfba2d-1617-453f-a416-52e6edb5f9a0",
        },
      },
      {
        jwks = {
          type     = "record",
          required = true,
          fields = {
            {
              keys = {
                type = "array",
                required = true,
                elements = oidcdefs.jwk,
              },
            },
          },
        },
      },
    },
  },
}
