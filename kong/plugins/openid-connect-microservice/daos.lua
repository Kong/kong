return {
  oic_issuers            = {
    primary_key          = { "issuer" },
    table                = "oic_issuers",
    fields               = {
      issuer             = {
        type             = "string"
      },
      configuration      = {
        type             = "text"
      },
      keys               = {
        type             = "text"
      },
      created_at         = {
        type             = "timestamp",
        immutable        = true,
        dao_insert_value = true
      },
    },
    marshall_event       = function(_, t)
      return {
        issuer           = t.issuer
      }
    end,
  },
  oic_revoked            = {
    primary_key          = { "hash" },
    table                = "oic_revoked",
    fields               = {
      hash               = {
        type             = "string"
      },
      created_at         = {
        type             = "timestamp",
        immutable        = true,
        dao_insert_value = true
      },
    },
    marshall_event       = function(_, t)
      return {
        hash             = t.hash
      }
    end
  }
}
