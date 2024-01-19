return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "cert_details" JSONB;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
      ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "version" INTEGER;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
      CREATE TABLE clustering_sync_version (
        "version" SERIAL PRIMARY KEY
      );

      CREATE TABLE clustering_sync_delta (
        "version" INT NOT NULL,
        "type" TEXT NOT NULL,
        "id" UUID NOT NULL,
        "ws_id" UUID NOT NULL,
        "row" JSON,
        FOREIGN KEY (version) REFERENCES clustering_sync_version(version)
      );
      END;
      $$;

      DO $$
      BEGIN
      CREATE TABLE IF NOT EXISTS "assets" (
        "id"           UUID                         UNIQUE,
        "name"         TEXT                         NOT NULL,
        "tags"         TEXT[],
        "url"          TEXT                         UNIQUE,
        "metadata"     JSONB                        NOT NULL,
        "created_at"   TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "updated_at"   TIMESTAMP WITH TIME ZONE     NOT NULL,
        "ws_id"        UUID                         REFERENCES "workspaces" ("id") ON DELETE CASCADE,

        PRIMARY KEY ("id")
      );

      ALTER TABLE IF EXISTS ONLY "plugins" ADD "asset_id" UUID REFERENCES "assets" ("id") ON DELETE CASCADE;

      ALTER TABLE IF EXISTS ONLY "assets" ADD CONSTRAINT "assets_ws_id_name_unique" UNIQUE ("ws_id", "name");
      
      CREATE INDEX IF NOT EXISTS "assets_name_idx" ON "assets" ("name");
      
      CREATE INDEX IF NOT EXISTS "assets_tags_idx" ON "assets" USING GIN ("tags");

      DROP TRIGGER IF EXISTS "assets_sync_tags_trigger" ON "assets";
      END$$;

      DO $$
      BEGIN
        CREATE TRIGGER "assets_sync_tags_trigger"
        AFTER INSERT OR UPDATE OF "tags"
                    OR DELETE ON "assets"
        FOR EACH ROW
        EXECUTE PROCEDURE "sync_tags" ();
      EXCEPTION WHEN undefined_column OR undefined_table THEN
        -- do nothing, accept existing state
      END$$;
    ]]
  }
}
