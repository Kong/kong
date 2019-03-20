return {
  postgres = {
    up = [[

      -- Unique constraint on "issuer" already adds btree index
      DROP INDEX IF EXISTS "oic_issuers_idx";

    ]],
  },

  cassandra = {
    up = [[
    ]],
  },
}
