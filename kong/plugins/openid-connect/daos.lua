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
        dao_insert_value = true,
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
        dao_insert_value = true,
      },
    },
  },
}
