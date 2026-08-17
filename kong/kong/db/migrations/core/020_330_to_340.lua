return {
  postgres = {
    up = [[
      DROP TABLE IF EXISTS "ttls";

      CREATE TABLE IF NOT EXISTS "filter_chains" (
        "id"          UUID                       PRIMARY KEY,
        "name"        TEXT                       UNIQUE,
        "enabled"     BOOLEAN                    DEFAULT TRUE,
        "route_id"    UUID                       REFERENCES "routes"     ("id") ON DELETE CASCADE,
        "service_id"  UUID                       REFERENCES "services"   ("id") ON DELETE CASCADE,
        "ws_id"       UUID                       REFERENCES "workspaces" ("id") ON DELETE CASCADE,
        "cache_key"   TEXT                       UNIQUE,
        "filters"     JSONB[],
        "tags"        TEXT[],
        "created_at"  TIMESTAMP WITH TIME ZONE,
        "updated_at"  TIMESTAMP WITH TIME ZONE
      );

      DO $$
      BEGIN
        CREATE UNIQUE INDEX IF NOT EXISTS "filter_chains_name_idx"
          ON "filter_chains" ("name");
      END$$;

      DO $$
      BEGIN
        CREATE UNIQUE INDEX IF NOT EXISTS "filter_chains_cache_key_idx"
          ON "filter_chains" ("cache_key");
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "filter_chains_tags_idx" ON "filter_chains" USING GIN ("tags");
      EXCEPTION WHEN UNDEFINED_COLUMN then
        -- do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS "filter_chains_sync_tags_trigger" ON "filter_chains";

      DO $$
      BEGIN
        CREATE TRIGGER "filter_chains_sync_tags_trigger"
        AFTER INSERT OR UPDATE OF "tags"
                    OR DELETE ON "filter_chains"
        FOR EACH ROW
        EXECUTE PROCEDURE "sync_tags" ();
      EXCEPTION WHEN undefined_column OR undefined_table THEN
        -- do nothing, accept existing state
      END$$;
    ]]
  }
}
