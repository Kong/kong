return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "basicauth_credentials" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "kongsumer_id"  UUID                         REFERENCES "kongsumers" ("id") ON DELETE CASCADE,
        "username"     TEXT                         UNIQUE,
        "password"     TEXT
      );

      CREATE INDEX IF NOT EXISTS "basicauth_kongsumer_id_idx" ON "basicauth_credentials" ("kongsumer_id");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS basicauth_credentials (
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        kongsumer_id uuid,
        password    text,
        username    text
      );
      CREATE INDEX IF NOT EXISTS ON basicauth_credentials(username);
      CREATE INDEX IF NOT EXISTS ON basicauth_credentials(kongsumer_id);
    ]],
  },
}
