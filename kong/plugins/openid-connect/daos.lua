return {
  oic_issuers            = {
    primary_key          = {
      "id",
    },
    cache_key            = {
      "issuer",
    },
    table                = "oic_issuers",
    fields               = {
      id                 = {
        type             = "id",
        dao_insert_value = true
      },
      issuer             = {
        type             = "url",
        unique           = true,
        required         = true,
      },
      configuration      = {
        type             = "text",
      },
      keys               = {
        type             = "text",
      },
      secret             = {
        type             = "text",
      },
      created_at         = {
        type             = "timestamp",
        immutable        = true,
        dao_insert_value = true
      },
    },
  },
  oic_signout            = {
    primary_key          = {
      "id",
    },
    table                = "oic_signout",
    fields               = {
      id                 = {
        type             = "id",
        dao_insert_value = true,
      },
      jti                = {
        type             = "text",
      },
      iss                = {
        type             = "text",
      },
      sid                = {
        type             = "text",
      },
      sub                = {
        type             = "text",
      },
      aud                = {
        type             = "text",
      },
      created_at         = {
        type             = "timestamp",
        immutable        = true,
        dao_insert_value = true,
      },
    },
  },
  oic_session            = {
    primary_key          = {
      "id",
    },
    table                = "oic_session",
    fields               = {
      id                 = {
        type             = "id",
        dao_insert_value = true,
      },
      sid                = {
        type             = "text",
        unique           = true,
        required         = true,
      },
      exp                = {
        type             = "number",
      },
      data                = {
        type             = "text",
      },
      created_at         = {
        type             = "timestamp",
        immutable        = true,
        dao_insert_value = true,
      },
    },
  },
  oic_revoked            = {
    primary_key          = {
      "id",
    },
    table                = "oic_revoked",
    fields               = {
      id                 = {
        type             = "id",
        dao_insert_value = true,
      },
      hash               = {
        type             = "text",
        unique           = true,
        required         = true,
      },
      exp                = {
        type             = "number",
      },
      created_at         = {
        type             = "timestamp",
        immutable        = true,
        dao_insert_value = true,
      },
    },
  },
}
