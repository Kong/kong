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
            ALTER TABLE IF EXISTS ONLY "upstreams" ADD "use_srv_name"  BOOLEAN DEFAULT false;
            EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
            END;
        $$;

        CREATE TABLE IF NOT EXISTS "key_sets" (
          "id"           UUID                       PRIMARY KEY,
          "name"         TEXT                       UNIQUE,
          "tags"         TEXT[],
          "ws_id"        UUID                       REFERENCES "workspaces" ("id"),
          "created_at"   TIMESTAMP WITH TIME ZONE,
          "updated_at"   TIMESTAMP WITH TIME ZONE
        );

        DO $$
        BEGIN
          CREATE INDEX IF NOT EXISTS "key_sets_tags_idx" ON "key_sets" USING GIN ("tags");
        EXCEPTION WHEN UNDEFINED_COLUMN then
          -- do nothing, accept existing state
        END$$;

        DROP TRIGGER IF EXISTS "key_sets_sync_tags_trigger" ON "key_sets";

        DO $$
        BEGIN
          CREATE TRIGGER "key_sets_sync_tags_trigger"
          AFTER INSERT OR UPDATE OF "tags"
                      OR DELETE ON "key_sets"
          FOR EACH ROW
          EXECUTE PROCEDURE "sync_tags" ();
        EXCEPTION WHEN undefined_column OR undefined_table THEN
          -- do nothing, accept existing state
        END$$;

        CREATE TABLE IF NOT EXISTS "keys" (
          "id"           UUID                       PRIMARY KEY,
          "set_id"       UUID                       REFERENCES "key_sets" ("id") on delete cascade,
          "name"         TEXT                       UNIQUE,
          "cache_key"    TEXT                       UNIQUE,
          "ws_id"        UUID                       REFERENCES "workspaces" ("id"),
          "kid"          TEXT,
          "jwk"          TEXT,
          "pem"          JSONB,
          "tags"         TEXT[],
          "created_at"   TIMESTAMP WITH TIME ZONE,
          "updated_at"   TIMESTAMP WITH TIME ZONE,
          UNIQUE ("kid", "set_id")
        );

        DO $$
        BEGIN
          CREATE INDEX IF NOT EXISTS "keys_fkey_key_sets" ON "keys" ("set_id");
        EXCEPTION WHEN undefined_column THEN
          -- do nothing, accept existing state
        END$$;

        DO $$
        BEGIN
          CREATE INDEX IF NOT EXISTS "keys_tags_idx" ON "keys" USING GIN ("tags");
        EXCEPTION WHEN undefined_column THEN
          -- do nothing, accept existing state
        END$$;

        DROP TRIGGER IF EXISTS "keys_sync_tags_trigger" ON "keys";

        DO $$
        BEGIN
          CREATE TRIGGER "keys_sync_tags_trigger"
          AFTER INSERT OR UPDATE OF "tags"
                      OR DELETE ON "keys"
          FOR EACH ROW
          EXECUTE PROCEDURE "sync_tags" ();
        EXCEPTION WHEN undefined_column or UNDEFINED_TABLE then
          -- do nothing, accept existing state
        END$$;
      ]]
    },
  }
