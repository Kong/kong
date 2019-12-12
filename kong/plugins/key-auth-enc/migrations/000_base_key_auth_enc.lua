return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "keyauth_enc_credentials" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "key"          TEXT                         UNIQUE,
        "key_ident"    TEXT
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "keyauth_enc_credentials_consum" ON "keyauth_enc_credentials" ("consumer_id");
        CREATE INDEX IF NOT EXISTS "keyauth_enc_credentials_consum" ON "keyauth_enc_credentials" ("key_ident");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      ALTER TABLE IF EXISTS ONLY "keyauth_enc_credentials"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyauth_enc_credentials(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        consumer_id uuid,
        key         text,
        key_ident   text
      );
      CREATE INDEX IF NOT EXISTS ON keyauth_enc_credentials(key);
      CREATE INDEX IF NOT EXISTS ON keyauth_enc_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS ON keyauth_enc_credentials(key_ident);
    ]],
  },
}
