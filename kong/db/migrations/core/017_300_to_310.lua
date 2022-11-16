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

    cassandra = {
      up = [[
        ALTER TABLE upstreams ADD use_srv_name boolean;
        create table if not exists keys (
          id           uuid,
          name         text,
          cache_key    text,
          ws_id        uuid,
          kid          text,
          jwk          text,
          pem          text,
          tags         set<text>,
          set_id       uuid,
          created_at   timestamp,
          updated_at   timestamp,
          PRIMARY KEY (id)
        );
        -- creating indexes for all queryable fields
        -- to avoid ALLOW_FILTERING requirements.
        create index if not exists keys_ws_id_idx on keys (ws_id);
        create index if not exists keys_set_id_idx on keys (set_id);
        create index if not exists keys_kid_idx on keys (kid);
        create index if not exists keys_name_idx on keys (name);
        create index if not exists keys_cache_key_idx on keys (cache_key);

        create table if not exists key_sets (
          id           uuid,
          name         text,
          ws_id        uuid,
          tags         set<text>,
          created_at   timestamp,
          updated_at   timestamp,
          PRIMARY KEY (id)
        );
        create index if not exists key_sets_ws_id_idx on key_sets (ws_id);
        create index if not exists key_sets_name_idx on key_sets (name);
      ]]
    },
  }
