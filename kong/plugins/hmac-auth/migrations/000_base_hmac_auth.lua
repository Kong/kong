return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "hmacauth_credentials" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "username"     TEXT                         UNIQUE,
        "secret"       TEXT
      );

      CREATE INDEX IF NOT EXISTS "hmacauth_credentials_consumer_id" ON "hmacauth_credentials" ("consumer_id");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS hmacauth_credentials(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        consumer_id uuid,
        username    text,
        secret      text
      );
      CREATE INDEX IF NOT EXISTS ON hmacauth_credentials(username);
      CREATE INDEX IF NOT EXISTS ON hmacauth_credentials(consumer_id);
    ]],
  },
}
