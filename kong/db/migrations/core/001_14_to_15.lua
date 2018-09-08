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



      ALTER TABLE IF EXISTS ONLY "plugins" DROP CONSTRAINT IF EXISTS "plugins_pkey";
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins" ADD PRIMARY KEY ("id");
      EXCEPTION WHEN DUPLICATE_TABLE THEN
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

      ALTER TABLE IF EXISTS ONLY "plugins" ALTER "config" TYPE JSONB USING "config"::JSONB;
    ]],

    teardown = function(connector, helpers)
      assert(connector:connect_migrations())

      for rows, err in connector:iterate('SELECT * FROM "plugins";') do
        if err then
          return nil, err
        end

        for i = 1, #rows do
          local row = rows[i]
          local cache_key = table.concat({
            "plugins",
            row.name,
            row.route_id or "",
            row.service_id or "",
            row.consumer_id or "",
            row.api_id or ""
          }, ":")

          local sql = string.format([[
            UPDATE "plugins" SET "cache_key" = '%s' WHERE "id" = '%s';
          ]], cache_key, row.id)

          assert(connector:query(sql))
        end
      end
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
    end,
  },
}
