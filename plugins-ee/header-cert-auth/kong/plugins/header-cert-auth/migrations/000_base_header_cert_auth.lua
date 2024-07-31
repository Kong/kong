-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "header_cert_auth_credentials" (
        "id"                        UUID                         PRIMARY KEY,
        "created_at"                TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"               UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE NOT NULL,
        "subject_name"              TEXT                         NOT NULL,
        "ca_certificate_id"         UUID                         REFERENCES "ca_certificates" ("id") ON DELETE CASCADE,
        "cache_key"                 TEXT                         UNIQUE,
        "tags"                      TEXT[],
        "ws_id"                     UUID                         REFERENCES "workspaces" ("id")
      );
      CREATE INDEX IF NOT EXISTS "header_cert_auth_common_name_idx" ON "header_cert_auth_credentials" ("subject_name");
      CREATE INDEX IF NOT EXISTS "header_cert_auth_consumer_id_idx" ON "header_cert_auth_credentials" ("consumer_id");
      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS header_cert_auth_credentials_tags_idx ON header_cert_auth_credentials USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
      DROP TRIGGER IF EXISTS header_cert_auth_credentials_sync_tags_trigger ON header_cert_auth_credentials;
      DO $$
      BEGIN
        CREATE TRIGGER header_cert_auth_credentials_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON header_cert_auth_credentials
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
