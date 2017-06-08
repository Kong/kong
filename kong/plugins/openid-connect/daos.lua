return {
  oic_issuers            = {
    primary_key          = { "id" },
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
      created_at         = {
        type             = "timestamp",
        immutable        = true,
        dao_insert_value = true
      },
    },
    marshall_event       = function(_, t)
      return {
        id               = t.id,
        issuer           = t.issuer,
      }
    end,
  },
  oic_signout            = {
    primary_key          = { "id" },
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
    marshall_event       = function(_, t)
      return {
        id               = t.id,
        sid              = t.sid,
        sub              = t.sub,
      }
    end
  },
  oic_session            = {
    primary_key          = { "id" },
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
    marshall_event       = function(_, t)
      return {
        id               = t.id,
        sid              = t.sid,
      }
    end
  },
  oic_revoked            = {
    primary_key          = { "id" },
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
    marshall_event       = function(_, t)
      return {
        id               = t.id,
        sid              = t.sid,
      }
    end
  },
}
