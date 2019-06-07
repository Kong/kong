return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        UPDATE consumers SET created_at = DATE_TRUNC('seconds', created_at);
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        UPDATE plugins SET created_at = DATE_TRUNC('seconds', created_at);
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        UPDATE upstreams SET created_at = DATE_TRUNC('seconds', created_at);
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        UPDATE targets SET created_at = DATE_TRUNC('milliseconds', created_at);
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DROP FUNCTION IF EXISTS "upsert_ttl" (TEXT, UUID, TEXT, TEXT, TIMESTAMP WITHOUT TIME ZONE);

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins" ADD "protocols" TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      CREATE TABLE IF NOT EXISTS "tags" (
        entity_id         UUID    PRIMARY KEY,
        entity_name       TEXT,
        tags              TEXT[]
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS tags_entity_name_idx ON tags(entity_name);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS tags_tags_idx ON tags USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      CREATE OR REPLACE FUNCTION sync_tags() RETURNS trigger
      LANGUAGE plpgsql
      AS $$
        BEGIN
          IF (TG_OP = 'TRUNCATE') THEN
            DELETE FROM tags WHERE entity_name = TG_TABLE_NAME;
            RETURN NULL;
          ELSIF (TG_OP = 'DELETE') THEN
            DELETE FROM tags WHERE entity_id = OLD.id;
            RETURN OLD;
          ELSE

          -- Triggered by INSERT/UPDATE
          -- Do an upsert on the tags table
          -- So we don't need to migrate pre 1.1 entities
          INSERT INTO tags VALUES (NEW.id, TG_TABLE_NAME, NEW.tags)
          ON CONFLICT (entity_id) DO UPDATE
                  SET tags=EXCLUDED.tags;
          END IF;
          RETURN NEW;
        END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY services ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS services_tags_idx ON services USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS services_sync_tags_trigger ON services;

      DO $$
      BEGIN
        CREATE TRIGGER services_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON services
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY routes ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS routes_tags_idx ON routes USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS routes_sync_tags_trigger ON routes;

      DO $$
      BEGIN
        CREATE TRIGGER routes_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON routes
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY certificates ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS certificates_tags_idx ON certificates USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS certificates_sync_tags_trigger ON certificates;

      DO $$
      BEGIN
        CREATE TRIGGER certificates_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON certificates
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY snis ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS snis_tags_idx ON snis USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS snis_sync_tags_trigger ON snis;

      DO $$
      BEGIN
        CREATE TRIGGER snis_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON snis
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY consumers ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS consumers_tags_idx ON consumers USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS consumers_sync_tags_trigger ON consumers;

      DO $$
      BEGIN
        CREATE TRIGGER consumers_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON consumers
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY plugins ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS plugins_tags_idx ON plugins USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS plugins_sync_tags_trigger ON plugins;

      DO $$
      BEGIN
        CREATE TRIGGER plugins_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON plugins
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY upstreams ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS upstreams_tags_idx ON upstreams USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS upstreams_sync_tags_trigger ON upstreams;

      DO $$
      BEGIN
        CREATE TRIGGER upstreams_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON upstreams
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY targets ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS targets_tags_idx ON targets USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS targets_sync_tags_trigger ON targets;

      DO $$
      BEGIN
        CREATE TRIGGER targets_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON targets
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE plugins ADD protocols set<text>;

      ALTER TABLE services ADD tags set<text>;
      ALTER TABLE routes ADD tags set<text>;
      ALTER TABLE certificates ADD tags set<text>;
      ALTER TABLE snis ADD tags set<text>;
      ALTER TABLE consumers ADD tags set<text>;
      ALTER TABLE plugins ADD tags set<text>;
      ALTER TABLE upstreams ADD tags set<text>;
      ALTER TABLE targets ADD tags set<text>;

      CREATE TABLE IF NOT EXISTS tags (
        tag               text,
        entity_name       text,
        entity_id         text,
        other_tags        set<text>,
        PRIMARY KEY       ((tag), entity_name, entity_id)
      );

    ]],
  },
}
