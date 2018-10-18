return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "name" TEXT UNIQUE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;



      CREATE INDEX IF NOT EXISTS "targets_upstream_id_idx" ON "targets" ("upstream_id");



      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins"
          DROP CONSTRAINT IF EXISTS "plugins_pkey",
          DROP CONSTRAINT IF EXISTS "plugins_id_key",
          ADD PRIMARY KEY ("id");
      EXCEPTION WHEN DUPLICATE_TABLE OR INVALID_TABLE_DEFINITION THEN
          -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins" ADD "cache_key" TEXT UNIQUE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;



      -- Unique constraint on "name" already adds btree index
      DROP INDEX IF EXISTS "apis_name_idx";

      -- Unique constraint on "name" already adds btree index
      DROP INDEX IF EXISTS "upstreams_name_idx";

      -- Unique constraint on "custom_id" already adds btree index
      DROP INDEX IF EXISTS "custom_id_idx";



      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "username_idx" RENAME TO "consumers_username_idx";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "ssl_certificates_pkey" RENAME TO "certificates_pkey";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "idx_cluster_events_at" RENAME TO "cluster_events_at_idx";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "idx_cluster_events_channel" RENAME TO "cluster_events_channel_idx";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "routes_fkey_service" RENAME TO "routes_service_id_idx";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "snis_fkey_certificate" RENAME TO "snis_certificate_id_idx";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "plugins_api_idx" RENAME TO "plugins_api_id_idx";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER INDEX IF EXISTS "plugins_consumer_idx" RENAME TO "plugins_consumer_id_idx";
      EXCEPTION WHEN DUPLICATE_TABLE THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "snis"
          RENAME CONSTRAINT "snis_name_unique" TO "snis_name_key";
      EXCEPTION
        WHEN UNDEFINED_OBJECT THEN
          -- Do nothing, accept existing state
        WHEN DUPLICATE_TABLE THEN
          -- Do nothing, accept existing state
      END;
      $$;



      ALTER TABLE IF EXISTS ONLY "apis"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC';

      ALTER TABLE IF EXISTS ONLY "consumers"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';

      ALTER TABLE IF EXISTS ONLY "plugins"
        ALTER "config"     TYPE JSONB USING "config"::JSONB,
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';

      ALTER TABLE IF EXISTS ONLY "upstreams"
        ALTER "healthchecks" TYPE JSONB USING "healthchecks"::JSONB,
        ALTER "created_at"   TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at"   SET DEFAULT CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC';

      ALTER TABLE IF EXISTS ONLY "targets"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC';
    ]],

    teardown = function(connector, helpers)
      assert(connector:connect_migrations())

      for row, err in connector:iterate('SELECT * FROM "plugins";') do
        if err then
          return nil, err
        end

        local cache_key = table.concat({
          "plugins",
          row.name,
          row.route_id    == ngx.null and "" or row.route_id,
          row.service_id  == ngx.null and "" or row.service_id,
          row.consumer_id == ngx.null and "" or row.consumer_id,
          row.api_id      == ngx.null and "" or row.api_id,
        }, ":")

        local sql = string.format([[
          UPDATE "plugins" SET "cache_key" = '%s' WHERE "id" = '%s';
        ]], cache_key, row.id)

        assert(connector:query(sql))
      end

      assert(connector:query('DROP TABLE IF EXISTS "schema_migrations" CASCADE;'))
    end,
  },

  cassandra = {
    up = [[
      ALTER TABLE routes ADD name text;
      CREATE INDEX IF NOT EXISTS routes_name_idx ON routes(name);



      CREATE TABLE IF NOT EXISTS plugins_temp(
        id uuid,
        created_at timestamp,
        api_id uuid,
        route_id uuid,
        service_id uuid,
        consumer_id uuid,
        name text,
        config text, -- serialized plugin configuration
        enabled boolean,
        cache_key text,
        PRIMARY KEY (id)
      );
    ]],

    teardown = function(connector, helpers)
      local plugins_def = {
        name = "plugins",
        columns = {
          id = "uuid",
          name = "text",
          config = "text",
          api_id = "uuid",
          route_id = "uuid",
          service_id = "uuid",
          consumer_id = "uuid",
          created_at = "timestamp",
          enabled = "boolean",
        },
        partition_keys = {},
      }

      local plugins_temp_def = {
        name = "plugins_temp",
        columns = {
          id = "uuid",
          name = "text",
          config = "text",
          api_id = "uuid",
          route_id = "uuid",
          service_id = "uuid",
          consumer_id = "uuid",
          created_at = "timestamp",
          enabled = "boolean",
          cache_key = "text",
        },
        partition_keys = {},
      }

      assert(helpers:copy_cassandra_records(plugins_def, plugins_temp_def, {
        id = "id",
        name = "name",
        config = "config",
        api_id = "api_id",
        route_id = "route_id",
        service_id = "service_id",
        consumer_id = "consumer_id",
        created_at = "created_at",
        enabled = "enabled",
        cache_key = function(row)
          return table.concat({
            "plugins",
            row.name,
            row.route_id or "",
            row.service_id or "",
            row.consumer_id or "",
            row.api_id or ""
          }, ":")
        end,
      }))

      assert(connector:query([[
        DROP INDEX IF EXISTS plugins_name_idx;
        DROP INDEX IF EXISTS plugins_api_id_idx;
        DROP INDEX IF EXISTS plugins_route_id_idx;
        DROP INDEX IF EXISTS plugins_service_id_idx;
        DROP INDEX IF EXISTS plugins_consumer_id_idx;
        DROP TABLE IF EXISTS plugins;

        CREATE TABLE IF NOT EXISTS plugins(
          id uuid,
          created_at timestamp,
          api_id uuid,
          route_id uuid,
          service_id uuid,
          consumer_id uuid,
          name text,
          config text, -- serialized plugin configuration
          enabled boolean,
          cache_key text,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON plugins(name);
        CREATE INDEX IF NOT EXISTS ON plugins(api_id);
        CREATE INDEX IF NOT EXISTS ON plugins(route_id);
        CREATE INDEX IF NOT EXISTS ON plugins(service_id);
        CREATE INDEX IF NOT EXISTS ON plugins(consumer_id);
        CREATE INDEX IF NOT EXISTS ON plugins(cache_key);
      ]]))

      plugins_def = {
        name    = "plugins",
        columns = {
          id = "uuid",
          name = "text",
          config = "text",
          api_id = "uuid",
          route_id = "uuid",
          service_id = "uuid",
          consumer_id = "uuid",
          created_at = "timestamp",
          enabled = "boolean",
          cache_key = "text",
        },
        partition_keys = {},
      }

      assert(helpers:copy_cassandra_records(plugins_temp_def, plugins_def, {
        id = "id",
        name = "name",
        config = "config",
        api_id = "api_id",
        route_id = "route_id",
        service_id = "service_id",
        consumer_id = "consumer_id",
        created_at = "created_at",
        enabled = "enabled",
        cache_key = "cache_key",
      }))

      assert(connector:query("DROP TABLE IF EXISTS plugins_temp"))
      assert(connector:query("DROP TABLE IF EXISTS schema_migrations"))
    end,
  },
}
