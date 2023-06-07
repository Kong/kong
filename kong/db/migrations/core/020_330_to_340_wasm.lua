return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "wasm_filter_chains" (
        "id"          UUID                       PRIMARY KEY,
        "enabled"     BOOLEAN                    DEFAULT TRUE,
        "route_id"    UUID                       REFERENCES "routes"     ("id") ON DELETE CASCADE,
        "service_id"  UUID                       REFERENCES "services"   ("id") ON DELETE CASCADE,
        "ws_id"       UUID                       REFERENCES "workspaces" ("id") ON DELETE CASCADE,
        "cache_key"   TEXT                       UNIQUE,
        "filters"     JSONB[],
        "tags"        TEXT[],
        "created_at"  TIMESTAMP WITH TIME ZONE,
        "updated_at"  TIMESTAMP WITH TIME ZONE,

        -- service and route are mutually exclusive
        CONSTRAINT "wasm_filter_chains_scope_ck"
          CHECK ((route_id IS NULL     AND service_id IS NOT NULL)
              OR (route_id IS NOT NULL AND service_id IS NULL))
      );

      DO $$
      BEGIN
      CREATE UNIQUE INDEX IF NOT EXISTS "wasm_filter_chains_cache_key_idx"
        ON "wasm_filter_chains" ("cache_key");
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
    ]],
  },
}
