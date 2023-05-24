-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "konnect_applications" (
        "id"            UUID      PRIMARY KEY,
        "ws_id"         UUID      REFERENCES "workspaces" ("id"),
        "created_at"    TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "client_id"     TEXT,
        "scopes"        TEXT[],
        "tags"          TEXT[],
        UNIQUE ("id", "ws_id"),
        UNIQUE ("client_id", "ws_id")
      );

      DROP TRIGGER IF EXISTS "konnect_applications_sync_tags_trigger" ON "konnect_applications";

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "konnect_applications_tags_idx" ON "konnect_applications" USING GIN ("tags");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE TRIGGER "konnect_applications_sync_tags_trigger"
        AFTER INSERT OR UPDATE OF "tags" OR DELETE ON "konnect_applications"
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
