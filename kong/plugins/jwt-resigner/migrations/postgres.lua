local migrations = {
  {
    name = "2018-08-20-180000_jwt_resigner",
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_resigner_jwks (
        id          UUID                      PRIMARY KEY,
        name        TEXT                      NOT NULL      UNIQUE,
        keys        JSONB                     NOT NULL,
        previous    JSONB,
        created_at  TIMESTAMP WITH TIME ZONE,
        updated_at  TIMESTAMP WITH TIME ZONE
      );
    ]],
    down = [[
      DROP TABLE jwt_resigner_jwks;
    ]]
  },
}

return migrations
