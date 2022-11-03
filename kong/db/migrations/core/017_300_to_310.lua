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

        create table if not exists "jwk_sets" (
          "id"           uuid                       primary key,
          "name"         text                       unique,
          "tags"         text[],
          "jwk_ttl"      bigint,
          "ttl"          timestamp with time zone,
          "created_at"   timestamp with time zone,
          "updated_at"   timestamp with time zone
        );

        do $$
        begin
          create index if not exists "jwk_sets_tags_idx" on "jwk_sets" using gin ("tags");
        exception when undefined_column then
          -- do nothing, accept existing state
        end$$;

        drop trigger if exists "jwk_sets_sync_tags_trigger" on "jwk_sets";

        do $$
        begin
          create trigger "jwk_sets_sync_tags_trigger"
          after insert or update of "tags"
                      or delete on "jwk_sets"
          for each row
          execute procedure "sync_tags" ();
        exception when undefined_column or undefined_table then
          -- do nothing, accept existing state
        end$$;

        do $$
        begin
          create index if not exists "jwk_sets_ttl_idx" on "jwk_sets" ("ttl");
        exception when undefined_table then
          -- do nothing, accept existing state
        end$$;


        create table if not exists "jwks" (
          "id"           uuid                       primary key,
          "set_id"       uuid                       references "jwk_sets"  ("id") on delete cascade,
          "name"         text                       unique,
          "cache_key"    text                       unique,
          "kid"          text,
          "jwk"          jsonb,
          "tags"         text[],
          "ttl"          timestamp with time zone,
          "created_at"   timestamp with time zone,
          "updated_at"   timestamp with time zone
        );

        do $$
        begin
          create index if not exists "jwks_fkey_jwk_sets" on "jwks" ("set_id");
        exception when undefined_column then
          -- do nothing, accept existing state
        end$$;

        do $$
        begin
          create index if not exists "jwks_tags_idx" on "jwks" using gin ("tags");
        exception when undefined_column then
          -- do nothing, accept existing state
        end$$;

        drop trigger if exists "jwks_sync_tags_trigger" on "jwks";

        do $$
        begin
          create trigger "jwks_sync_tags_trigger"
          after insert or update of "tags"
                      or delete on "jwks"
          for each row
          execute procedure "sync_tags" ();
        exception when undefined_column or undefined_table then
          -- do nothing, accept existing state
        end$$;

        do $$
        begin
          create index if not exists "jwks_ttl_idx" on "jwks" ("ttl");
        exception when undefined_table then
          -- do nothing, accept existing state
        end$$;
      ]]
    },

    cassandra = {
      up = [[
        ALTER TABLE upstreams ADD use_srv_name boolean;
        CREATE TABLE IF NOT EXISTS jwk_sets (
        id            uuid PRIMARY KEY,
        name          text,
        tags          set<text>,
        jwk_ttl       int,
        created_at    timestamp,
        updated_at    timestamp
      );
      CREATE INDEX IF NOT EXISTS ON jwk_sets (name);
      CREATE TABLE IF NOT EXISTS jwks (
        id            uuid PRIMARY KEY,
        set_id        uuid,
        name          text,
        cache_key     text,
        kid           text,
        jwk           text,
        tags          set<text>,
        created_at    timestamp,
        updated_at    timestamp
      );
      CREATE INDEX IF NOT EXISTS ON jwks (set_id);
      CREATE INDEX IF NOT EXISTS ON jwks (name);
      ]]
    },
  }
