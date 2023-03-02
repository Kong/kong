return {
  postgres = {
    up = [[
      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "ca_certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "consumers" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "snis" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "targets" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "workspaces" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      CREATE OR REPLACE FUNCTION batch_delete_expired_rows() RETURNS trigger
      LANGUAGE plpgsql
      AS $$
        BEGIN
          EXECUTE FORMAT('WITH rows AS (SELECT ctid FROM %s WHERE %s < CURRENT_TIMESTAMP AT TIME ZONE ''UTC'' ORDER BY %s LIMIT 2 FOR UPDATE SKIP LOCKED) DELETE FROM %s WHERE ctid IN (TABLE rows)', TG_TABLE_NAME, TG_ARGV[0], TG_ARGV[0], TG_TABLE_NAME);
          RETURN NULL;
        END;
      $$;

      DROP TRIGGER IF EXISTS "cluster_events_ttl_trigger" ON "cluster_events";

      DO $$
      BEGIN
        CREATE TRIGGER "cluster_events_ttl_trigger"
        AFTER INSERT ON "cluster_events"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("expire_at");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DROP TRIGGER IF EXISTS "clustering_data_planes_ttl_trigger" ON "clustering_data_planes";

      DO $$
      BEGIN
        CREATE TRIGGER "clustering_data_planes_ttl_trigger"
        AFTER INSERT ON "clustering_data_planes"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("ttl");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

      CREATE TABLE IF NOT EXISTS "wasm_filter_chains" (
        "id"          UUID                       PRIMARY KEY,
        "name"        TEXT                       UNIQUE,
        "enabled"     BOOLEAN                    DEFAULT TRUE,
        "route_id"    UUID                       REFERENCES "routes"     ("id") ON DELETE CASCADE,
        "service_id"  UUID                       REFERENCES "services"   ("id") ON DELETE CASCADE,
        "ws_id"       UUID                       REFERENCES "workspaces" ("id") ON DELETE CASCADE,
        "protocols"   TEXT[],
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
    ]],
  },
}
