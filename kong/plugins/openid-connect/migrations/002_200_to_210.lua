return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "oic_jwks" (
        "id"    UUID    PRIMARY KEY,
        "jwks"  JSONB
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS oic_jwks (
        id   uuid  PRIMARY KEY,
        jwks text
      );
    ]],
  },
}
