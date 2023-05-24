-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        -- we don't want to recreate vaults_beta again, if this migration is ran twice
        IF (SELECT to_regclass('vaults_tags_idx')) IS NULL THEN
          CREATE TABLE IF NOT EXISTS "vaults_beta" (
            "id"           UUID                      PRIMARY KEY,
            "ws_id"        UUID                      REFERENCES "workspaces" ("id"),
            "prefix"       TEXT                      UNIQUE,
            "name"         TEXT                      NOT NULL,
            "description"  TEXT,
            "config"       JSONB                     NOT NULL,
            "created_at"   TIMESTAMP WITH TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
            "updated_at"   TIMESTAMP WITH TIME ZONE,
            "tags"         TEXT[],
            UNIQUE ("id", "ws_id"),
            UNIQUE ("prefix", "ws_id")
          );

          DROP TRIGGER IF EXISTS "vaults_beta_sync_tags_trigger" ON "vaults_beta";

          BEGIN
            CREATE INDEX IF NOT EXISTS "vaults_beta_tags_idx" ON "vaults_beta" USING GIN ("tags");
          EXCEPTION WHEN UNDEFINED_COLUMN THEN
            -- Do nothing, accept existing state
          END;

          BEGIN
            CREATE TRIGGER "vaults_beta_sync_tags_trigger"
            AFTER INSERT OR UPDATE OF "tags" OR DELETE ON "vaults_beta"
            FOR EACH ROW
            EXECUTE PROCEDURE sync_tags();
          EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
            -- Do nothing, accept existing state
          END;
        END IF;
      END$$;
    ]]
  },
}
