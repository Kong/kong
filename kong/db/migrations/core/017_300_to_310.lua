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

        create table if not exists "key_sets" (
          "id"           uuid                       primary key,
          "name"         text                       unique,
          "tags"         text[],
          "ws_id"        UUID                       REFERENCES "workspaces" ("id"),
          "created_at"   timestamp with time zone,
          "updated_at"   timestamp with time zone
        );

        do $$
        begin
          create index if not exists "key_sets_tags_idx" on "key_sets" using gin ("tags");
        exception when undefined_column then
          -- do nothing, accept existing state
        end$$;

        drop trigger if exists "key_sets_sync_tags_trigger" on "key_sets";

        do $$
        begin
          create trigger "key_sets_sync_tags_trigger"
          after insert or update of "tags"
                      or delete on "key_sets"
          for each row
          execute procedure "sync_tags" ();
        exception when undefined_column or undefined_table then
          -- do nothing, accept existing state
        end$$;

        create table if not exists "keys" (
          "id"           uuid                       primary key,
          "set_id"       uuid                       REFERENCES "key_sets" ("id") on delete cascade,
          "name"         text                       unique,
          "cache_key"    text                       unique,
          "ws_id"        UUID                       REFERENCES "workspaces" ("id"),
          "kid"          text,                      unique ("kid", "set_id"),
          "jwk"          text,
          "pem"          jsonb,
          "tags"         text[],
          "created_at"   timestamp with time zone,
          "updated_at"   timestamp with time zone
        );

        do $$
        begin
          create index if not exists "keys_fkey_key_sets" on "keys" ("set_id");
        exception when undefined_column then
          -- do nothing, accept existing state
        end$$;

        do $$
        begin
          create index if not exists "keys_tags_idx" on "keys" using gin ("tags");
        exception when undefined_column then
          -- do nothing, accept existing state
        end$$;

        drop trigger if exists "keys_sync_tags_trigger" on "keys";

        do $$
        begin
          create trigger "keys_sync_tags_trigger"
          after insert or update of "tags"
                      or delete on "keys"
          for each row
          execute procedure "sync_tags" ();
        exception when undefined_column or undefined_table then
          -- do nothing, accept existing state
        end$$;
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
