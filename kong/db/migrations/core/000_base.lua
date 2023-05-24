return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "cluster_events" (
        "id"         UUID                       PRIMARY KEY,
        "node_id"    UUID                       NOT NULL,
        "at"         TIMESTAMP WITH TIME ZONE   NOT NULL,
        "nbf"        TIMESTAMP WITH TIME ZONE,
        "expire_at"  TIMESTAMP WITH TIME ZONE   NOT NULL,
        "channel"    TEXT,
        "data"       TEXT
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "cluster_events_at_idx" ON "cluster_events" ("at");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "cluster_events_channel_idx" ON "cluster_events" ("channel");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      CREATE OR REPLACE FUNCTION "delete_expired_cluster_events" () RETURNS TRIGGER
      LANGUAGE plpgsql
      AS $$
        BEGIN
          DELETE FROM "cluster_events"
                WHERE "expire_at" <= CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
          RETURN NEW;
        END;
      $$;

      DROP TRIGGER IF EXISTS "delete_expired_cluster_events_trigger" ON "cluster_events";
      CREATE TRIGGER "delete_expired_cluster_events_trigger"
        AFTER INSERT ON "cluster_events"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE delete_expired_cluster_events();



      CREATE TABLE IF NOT EXISTS "services" (
        "id"               UUID                       PRIMARY KEY,
        "created_at"       TIMESTAMP WITH TIME ZONE,
        "updated_at"       TIMESTAMP WITH TIME ZONE,
        "name"             TEXT                       UNIQUE,
        "retries"          BIGINT,
        "protocol"         TEXT,
        "host"             TEXT,
        "port"             BIGINT,
        "path"             TEXT,
        "connect_timeout"  BIGINT,
        "write_timeout"    BIGINT,
        "read_timeout"     BIGINT
      );



      CREATE TABLE IF NOT EXISTS "routes" (
        "id"              UUID                       PRIMARY KEY,
        "created_at"      TIMESTAMP WITH TIME ZONE,
        "updated_at"      TIMESTAMP WITH TIME ZONE,
        "name"            TEXT                       UNIQUE,
        "service_id"      UUID                       REFERENCES "services" ("id"),
        "protocols"       TEXT[],
        "methods"         TEXT[],
        "hosts"           TEXT[],
        "paths"           TEXT[],
        "snis"            TEXT[],
        "sources"         JSONB[],
        "destinations"    JSONB[],
        "regex_priority"  BIGINT,
        "strip_path"      BOOLEAN,
        "preserve_host"   BOOLEAN
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "routes_service_id_idx" ON "routes" ("service_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      CREATE TABLE IF NOT EXISTS "certificates" (
        "id"          UUID                       PRIMARY KEY,
        "created_at"  TIMESTAMP WITH TIME ZONE   DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "cert"        TEXT,
        "key"         TEXT
      );



      CREATE TABLE IF NOT EXISTS "snis" (
        "id"              UUID                       PRIMARY KEY,
        "created_at"      TIMESTAMP WITH TIME ZONE   DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "name"            TEXT                       NOT NULL UNIQUE,
        "certificate_id"  UUID                       REFERENCES "certificates" ("id")
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "snis_certificate_id_idx" ON "snis" ("certificate_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      CREATE TABLE IF NOT EXISTS "consumers" (
        "id"          UUID                         PRIMARY KEY,
        "created_at"  TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "username"    TEXT                         UNIQUE,
        "custom_id"   TEXT                         UNIQUE
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "consumers_username_idx" ON "consumers" (LOWER("username"));
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      CREATE TABLE IF NOT EXISTS "plugins" (
        "id"           UUID                         UNIQUE,
        "created_at"   TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "name"         TEXT                         NOT NULL,
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "service_id"   UUID                         REFERENCES "services"  ("id") ON DELETE CASCADE,
        "route_id"     UUID                         REFERENCES "routes"    ("id") ON DELETE CASCADE,
        "config"       JSONB                        NOT NULL,
        "enabled"      BOOLEAN                      NOT NULL,
        "cache_key"    TEXT                         UNIQUE,
        "run_on"       TEXT,

        PRIMARY KEY ("id")
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "plugins_name_idx" ON "plugins" ("name");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "plugins_consumer_id_idx" ON "plugins" ("consumer_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "plugins_service_id_idx" ON "plugins" ("service_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "plugins_route_id_idx" ON "plugins" ("route_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "plugins_run_on_idx" ON "plugins" ("run_on");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      CREATE TABLE IF NOT EXISTS "upstreams" (
        "id"                    UUID                         PRIMARY KEY,
        "created_at"            TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC'),
        "name"                  TEXT                         UNIQUE,
        "hash_on"               TEXT,
        "hash_fallback"         TEXT,
        "hash_on_header"        TEXT,
        "hash_fallback_header"  TEXT,
        "hash_on_cookie"        TEXT,
        "hash_on_cookie_path"   TEXT,
        "slots"                 INTEGER                      NOT NULL,
        "healthchecks"          JSONB
      );



      CREATE TABLE IF NOT EXISTS "targets" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC'),
        "upstream_id"  UUID                         REFERENCES "upstreams" ("id") ON DELETE CASCADE,
        "target"       TEXT                         NOT NULL,
        "weight"       INTEGER                      NOT NULL
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "targets_target_idx" ON "targets" ("target");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "targets_upstream_id_idx" ON "targets" ("upstream_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      CREATE TABLE IF NOT EXISTS "cluster_ca" (
        "pk"    BOOLEAN  NOT NULL  PRIMARY KEY CHECK(pk=true),
        "key"   TEXT     NOT NULL,
        "cert"  TEXT     NOT NULL
      );


      -- TODO: delete on 1.0.0 migrations
      CREATE TABLE IF NOT EXISTS "ttls" (
        "primary_key_value"  TEXT                         NOT NULL,
        "primary_uuid_value" UUID,
        "table_name"         TEXT                         NOT NULL,
        "primary_key_name"   TEXT                         NOT NULL,
        "expire_at"          TIMESTAMP WITHOUT TIME ZONE  NOT NULL,

        PRIMARY KEY ("primary_key_value", "table_name")
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "ttls_primary_uuid_value_idx" ON "ttls" ("primary_uuid_value");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      CREATE OR REPLACE FUNCTION "upsert_ttl" (v_primary_key_value TEXT, v_primary_uuid_value UUID, v_primary_key_name TEXT, v_table_name TEXT, v_expire_at TIMESTAMP WITHOUT TIME ZONE) RETURNS void
      LANGUAGE plpgsql
      AS $$
        BEGIN
          LOOP
            UPDATE ttls
               SET expire_at = v_expire_at
             WHERE primary_key_value = v_primary_key_value
               AND table_name = v_table_name;

            IF FOUND then
              RETURN;
            END IF;

            BEGIN
              INSERT INTO ttls (primary_key_value, primary_uuid_value, primary_key_name, table_name, expire_at)
                   VALUES (v_primary_key_value, v_primary_uuid_value, v_primary_key_name, v_table_name, v_expire_at);
              RETURN;
            EXCEPTION WHEN unique_violation THEN

            END;
          END LOOP;
        END;
        $$;
    ]]
  },
}
