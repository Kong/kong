return {
  jwt_resigner_jwks = {
    primary_key = {
      "id",
    },
    cache_key   = {
      "name",
    },
    table       = "jwt_resigner_jwks",
    fields      = {
      id                 = {
        type             = "id",
        dao_insert_value = true,
        required         = true,
      },
      name               = {
        type             = "text",
        unique           = true,
        required         = true,
      },
      keys               = {
        type             = "text",
        required         = true,
      },
      previous           = {
        type             = "text",
        required         = false,
      },
      created_at         = {
        type             = "timestamp",
        dao_insert_value = true,
        immutable        = true,
      },
      updated_at         = {
        type             = "timestamp",
        immutable        = false,
        dao_insert_value = true,
      },
    },
  },
}
