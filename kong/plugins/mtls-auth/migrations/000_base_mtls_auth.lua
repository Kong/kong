return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "mtls_auth_credentials" (
        "id"                        UUID                         PRIMARY KEY,
        "created_at"                TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"               UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE NOT NULL,
        "subject_name"              TEXT                         NOT NULL,
        "ca_certificate_id"         UUID                         REFERENCES "ca_certificates" ("id") ON DELETE CASCADE,
        "cache_key"                 TEXT                         UNIQUE
      );
      CREATE INDEX IF NOT EXISTS "mtls_auth_common_name_idx" ON "mtls_auth_credentials" ("subject_name");
      CREATE INDEX IF NOT EXISTS "mtls_auth_consumer_id_idx" ON "mtls_auth_credentials" ("consumer_id");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS mtls_auth_credentials(
        id                      uuid PRIMARY KEY,
        created_at              timestamp,
        consumer_id             uuid,
        subject_name            text,
        ca_certificate_id       uuid,
        cache_key               text,
      );
      CREATE INDEX IF NOT EXISTS ON mtls_auth_credentials(subject_name);
      CREATE INDEX IF NOT EXISTS ON mtls_auth_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS ON mtls_auth_credentials(ca_certificate_id);
      CREATE INDEX IF NOT EXISTS mtls_auth_credentials_cache_key_idx ON mtls_auth_credentials(cache_key);
    ]],
  },
}
