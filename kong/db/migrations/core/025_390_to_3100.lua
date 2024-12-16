-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "custom_plugins" (
        "id"           UUID                      PRIMARY KEY,
        "ws_id"        UUID                      REFERENCES "workspaces" ("id"),
        "name"         TEXT                      NOT NULL UNIQUE,
        "schema"       TEXT                      NOT NULL,
        "handler"      TEXT                      NOT NULL,
        "created_at"   TIMESTAMP WITH TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "updated_at"   TIMESTAMP WITH TIME ZONE,
        "tags"         TEXT[],
        UNIQUE ("id", "ws_id"),
        UNIQUE ("name", "ws_id")
      );

      DROP TRIGGER IF EXISTS "custom_plugins_sync_tags_trigger" ON "custom_plugins";

      DO $$
        BEGIN
          CREATE INDEX IF NOT EXISTS "custom_plugins_tags_idx" ON "custom_plugins" USING GIN ("tags");
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END;
      $$;

      DO $$
        BEGIN
          CREATE TRIGGER "custom_plugins_sync_tags_trigger"
          AFTER INSERT OR UPDATE OF "tags" OR DELETE ON "custom_plugins"
          FOR EACH ROW
          EXECUTE PROCEDURE sync_tags();
        EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
          -- Do nothing, accept existing state
        END;
      $$;
    ]]
  }
}
