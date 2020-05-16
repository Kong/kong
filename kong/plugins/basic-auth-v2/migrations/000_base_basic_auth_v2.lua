return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "basicauth_credentials_v2" (
        "id"           UUID,
        "created_at"   TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "username"     TEXT                         UNIQUE,
        "password"     TEXT,
        "tags"         TEXT[],
        PRIMARY KEY("username", "id")
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "basicauth_consumer_id_idx" ON "basicauth_credentials_v2" ("consumer_id");
        CREATE INDEX IF NOT EXISTS "basicauth_x_tags_idx" ON "basicauth_credentials_v2" USING GIN ("tags");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS basicauth_credentials_v2 (
        id          uuid,
        created_at  timestamp,
        consumer_id uuid,
        password    text,
        username    text,
        tags        set<text>,
        PRIMARY KEY(username, id)
      );
      CREATE INDEX IF NOT EXISTS ON basicauth_credentials_v2(consumer_id);
    ]],
  },
}
