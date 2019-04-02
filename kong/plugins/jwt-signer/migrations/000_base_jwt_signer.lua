return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_signer_jwks (
        id          UUID                      PRIMARY KEY,
        name        TEXT                      NOT NULL      UNIQUE,
        keys        JSONB                     NOT NULL,
        previous    JSONB,
        created_at  TIMESTAMP WITH TIME ZONE,
        updated_at  TIMESTAMP WITH TIME ZONE
      );
    ]],
  },
  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_signer_jwks (
        id          UUID       PRIMARY KEY,
        name        TEXT,
        keys        TEXT,
        previous    TEXT,
        created_at  TIMESTAMP,
        updated_at  TIMESTAMP,
      );

      CREATE INDEX IF NOT EXISTS jwt_signer_jwks_name_idx ON jwt_signer_jwks(name);
    ]],
  },
}
