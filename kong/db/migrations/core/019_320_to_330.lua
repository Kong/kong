return {
    postgres = {
      up = [[
        CREATE TABLE IF NOT EXISTS "wasm_filter_chains" (
          "id"          UUID                       PRIMARY KEY,
          "name"        TEXT                       UNIQUE,
          "enabled"     BOOLEAN                    DEFAULT TRUE,
          "route_id"    UUID                       REFERENCES "routes"     ("id") ON DELETE CASCADE,
          "service_id"  UUID                       REFERENCES "services"   ("id") ON DELETE CASCADE,
          "ws_id"       UUID                       REFERENCES "workspaces" ("id") ON DELETE CASCADE,
          "filters"     JSONB[],
          "tags"        TEXT[],
          "created_at"  TIMESTAMP WITH TIME ZONE,
          "updated_at"  TIMESTAMP WITH TIME ZONE
        );

        DO $$
        BEGIN
          CREATE INDEX IF NOT EXISTS "wasm_filter_chains_name_idx" ON "wasm_filter_chains" ("name");
        EXCEPTION WHEN UNDEFINED_COLUMN then
          -- do nothing, accept existing state
        END$$;


        DO $$
        BEGIN
          CREATE INDEX IF NOT EXISTS "wasm_filter_chains_tags_idx" ON "wasm_filter_chains" USING GIN ("tags");
        EXCEPTION WHEN UNDEFINED_COLUMN then
          -- do nothing, accept existing state
        END$$;

        DROP TRIGGER IF EXISTS "wasm_filter_chains_sync_tags_trigger" ON "wasm_filter_chains";

        DO $$
        BEGIN
          CREATE TRIGGER "wasm_filter_chains_sync_tags_trigger"
          AFTER INSERT OR UPDATE OF "tags"
                      OR DELETE ON "wasm_filter_chains"
          FOR EACH ROW
          EXECUTE PROCEDURE "sync_tags" ();
        EXCEPTION WHEN undefined_column OR undefined_table THEN
          -- do nothing, accept existing state
        END$$;
      ]]
    },

    cassandra = {
      up = [[
      ]]
    },
  }
