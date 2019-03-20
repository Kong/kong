return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "jwt_secrets" (
        "id"              UUID                         PRIMARY KEY,
        "created_at"      TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "kongsumer_id"     UUID                         REFERENCES "kongsumers" ("id") ON DELETE CASCADE,
        "key"             TEXT                         UNIQUE,
        "secret"          TEXT,
        "algorithm"       TEXT,
        "rsa_public_key"  TEXT
      );

      CREATE INDEX IF NOT EXISTS "jwt_secrets_kongsumer_id" ON "jwt_secrets" ("kongsumer_id");
      CREATE INDEX IF NOT EXISTS "jwt_secrets_secret"      ON "jwt_secrets" ("secret");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_secrets(
        id             uuid PRIMARY KEY,
        created_at     timestamp,
        kongsumer_id    uuid,
        algorithm      text,
        rsa_public_key text,
        key            text,
        secret         text
      );
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(key);
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(secret);
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(kongsumer_id);
    ]],
  },
}
