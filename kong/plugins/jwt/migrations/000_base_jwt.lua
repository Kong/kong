return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "jwt_secrets" (
        "id"              UUID                         PRIMARY KEY,
        "created_at"      TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"     UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "key"             TEXT                         UNIQUE,
        "secret"          TEXT,
        "algorithm"       TEXT,
        "rsa_public_key"  TEXT
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "jwt_secrets_consumer_id_idx" ON "jwt_secrets" ("consumer_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "jwt_secrets_secret_idx" ON "jwt_secrets" ("secret");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_secrets(
        id             uuid PRIMARY KEY,
        created_at     timestamp,
        consumer_id    uuid,
        algorithm      text,
        rsa_public_key text,
        key            text,
        secret         text
      );
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(key);
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(secret);
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(consumer_id);
    ]],
  },
}
