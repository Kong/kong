return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "keyauth_credentials" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "kongsumer_id"  UUID                         REFERENCES "kongsumers" ("id") ON DELETE CASCADE,
        "key"          TEXT                         UNIQUE
      );

      CREATE INDEX IF NOT EXISTS "keyauth_kongsumer_idx" ON "keyauth_credentials" ("kongsumer_id");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        kongsumer_id uuid,
        key         text
      );
      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(key);
      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(kongsumer_id);
    ]],
  },
}
