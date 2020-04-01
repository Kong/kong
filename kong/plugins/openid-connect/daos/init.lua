local typedefs = require "kong.db.schema.typedefs"


local jwk = {
  type = "record",
  required = true,
  fields = {
    {
      issuer = {
        type = "string",
        required = false,
      },
    },
    {
      kty = {
        type = "string",
        required = false,
      },
    },
    {
      use = {
        type = "string",
        required = false,
      },
    },
    {
      key_ops = {
        type = "array",
        required = false,
        elements = {
          type = "string",
          required = false,
        }
      },
    },
    {
      alg = {
        type = "string",
        required = false,
      },
    },
    {
      kid = {
        type = "string",
        required = true,
      },
    },
    {
      x5u = {
        type = "string",
        required = false,
      },
    },
    {
      x5c = {
        type = "array",
        required = false,
        elements = {
          type = "string",
          required = false,
        },
      },
    },
    {
      x5t = {
        type = "string",
        required = false,
      },
    },
    {
      ["x5t#S256"] = {
        type = "string",
        required = false,
      },
    },
    {
      k = {
        type = "string",
        required = false,
      },
    },
    {
      x = {
        type = "string",
        required = false,
      },
    },
    {
      y = {
        type = "string",
        required = false,
      },
    },
    {
      crv = {
        type = "string",
        required = false,
      },
    },
    {
      n = {
        type = "string",
        required = false,
      },
    },
    {
      e = {
        type = "string",
        required = false,
      },
    },
    {
      d = {
        type = "string",
        required = false,
      },
    },
    {
      p = {
        type = "string",
        required = false,
      },
    },
    {
      q = {
        type = "string",
        required = false,
      },
    },
    {
      dp = {
        type = "string",
        required = false,
      },
    },
    {
      dq = {
        type = "string",
        required = false,
      },
    },
    {
      qi = {
        type = "string",
        required = false,
      },
    },
  },
}


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
        id = typedefs.uuid,
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
                elements = jwk,
              },
            },
          },
        },
      },
    },
  },
}
