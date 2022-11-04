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
          "keyset_ttl"      bigint,
          "ttl"          timestamp with time zone,
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

        do $$
        begin
          create index if not exists "key_sets_ttl_idx" on "key_sets" ("ttl");
        exception when undefined_table then
          -- do nothing, accept existing state
        end$$;


        create table if not exists "keys" (
          "id"           uuid                       primary key,
          "set_id"       uuid                       references "key_sets"  ("id") on delete cascade,
          "name"         text                       unique,
          "cache_key"    text                       unique,
          "kid"          text,
          "key_type"     text,
          "jwk"          jsonb,
          "pem"          jsonb,
          "tags"         text[],
          "ttl"          timestamp with time zone,
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

        do $$
        begin
          create index if not exists "keys_ttl_idx" on "keys" ("ttl");
        exception when undefined_table then
          -- do nothing, accept existing state
        end$$;
      ]]
    },

    cassandra = {
      up = [[
        ALTER TABLE upstreams ADD use_srv_name boolean;
      ]]
    },
  }
