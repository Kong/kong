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

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS "routes" ADD "snis" TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "sources" JSONB[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "destinations" JSONB[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;



      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "targets_upstream_id_idx" ON "targets" ("upstream_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins"
          DROP CONSTRAINT IF EXISTS "plugins_pkey";
      EXCEPTION WHEN DUPLICATE_TABLE OR INVALID_TABLE_DEFINITION THEN
          -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins"
          DROP CONSTRAINT IF EXISTS "plugins_id_key";
      EXCEPTION WHEN DUPLICATE_TABLE OR INVALID_TABLE_DEFINITION THEN
          -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins"
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
        CREATE INDEX IF NOT EXISTS "snis_certificate_id_idx" ON "snis" ("certificate_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

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
      EXCEPTION WHEN UNDEFINED_OBJECT OR DUPLICATE_TABLE THEN
          -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins" ADD "run_on" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "plugins_run_on_idx" ON "plugins" ("run_on");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "apis"
          ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
          ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC';
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "consumers"
          ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
          ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins"
          ALTER "config" TYPE JSONB USING "config"::JSONB;
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins"
          ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
          ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "upstreams"
          ALTER "healthchecks" TYPE JSONB USING "healthchecks"::JSONB;
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "upstreams"
          ALTER "created_at"   TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
          ALTER "created_at"   SET DEFAULT CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC';
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "targets"
          ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
          ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC';
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;



      CREATE TABLE IF NOT EXISTS "cluster_ca" (
        "pk"    BOOLEAN  NOT NULL  PRIMARY KEY CHECK(pk=true),
        "key"   TEXT     NOT NULL,
        "cert"  TEXT     NOT NULL
      );
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
      ALTER TABLE routes ADD snis set<text>;
      ALTER TABLE routes ADD sources set<text>;
      ALTER TABLE routes ADD destinations set<text>;
      ALTER TABLE plugins ADD run_on text;
      CREATE INDEX IF NOT EXISTS routes_name_idx ON routes(name);


      CREATE TABLE IF NOT EXISTS plugins_temp(
        id uuid,
        created_at timestamp,
        api_id uuid,
        route_id uuid,
        service_id uuid,
        consumer_id uuid,
        run_on text,
        name text,
        config text, -- serialized plugin configuration
        enabled boolean,
        cache_key text,
        PRIMARY KEY (id)
      );



      CREATE TABLE IF NOT EXISTS cluster_ca(
        pk boolean PRIMARY KEY,
        key text,
        cert text
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
          run_on = "text",
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
          run_on text,
          name text,
          config text, -- serialized plugin configuration
          enabled boolean,
          cache_key text,
          protocols set<text>, -- added in 1.1.0
          tags set<text>, -- added in 1.1.0
          PRIMARY KEY (id)
        );
      ]]))

      local _, err = connector:query("CREATE INDEX IF NOT EXISTS ON plugins(name)")
      if err and not (string.find(err, "Column .- was not found in table")       or
                      string.find(err, "[Ii]nvalid column name")                 or
                      string.find(err, "[Uu]ndefined column name")               or
                      string.find(err, "No column definition found for column")  or
                      string.find(err, "Undefined name .- in selection clause")) then
        return nil, err
      end

      _, err = connector:query("CREATE INDEX IF NOT EXISTS ON plugins(api_id)")
      if err and not (string.find(err, "Column .- was not found in table")       or
                      string.find(err, "[Ii]nvalid column name")                 or
                      string.find(err, "[Uu]ndefined column name")               or
                      string.find(err, "No column definition found for column")  or
                      string.find(err, "Undefined name .- in selection clause")) then
        return nil, err
      end

      _, err = connector:query("CREATE INDEX IF NOT EXISTS ON plugins(route_id)")
      if err and not (string.find(err, "Column .- was not found in table")       or
                      string.find(err, "[Ii]nvalid column name")                 or
                      string.find(err, "[Uu]ndefined column name")               or
                      string.find(err, "No column definition found for column")  or
                      string.find(err, "Undefined name .- in selection clause")) then
        return nil, err
      end

      _, err = connector:query("CREATE INDEX IF NOT EXISTS ON plugins(service_id)")
      if err and not (string.find(err, "Column .- was not found in table")       or
                      string.find(err, "[Ii]nvalid column name")                 or
                      string.find(err, "[Uu]ndefined column name")               or
                      string.find(err, "No column definition found for column")  or
                      string.find(err, "Undefined name .- in selection clause")) then
        return nil, err
      end

      _, err = connector:query("CREATE INDEX IF NOT EXISTS ON plugins(consumer_id)")
      if err and not (string.find(err, "Column .- was not found in table")       or
                      string.find(err, "[Ii]nvalid column name")                 or
                      string.find(err, "[Uu]ndefined column name")               or
                      string.find(err, "No column definition found for column")  or
                      string.find(err, "Undefined name .- in selection clause")) then
        return nil, err
      end

      _, err = connector:query("CREATE INDEX IF NOT EXISTS ON plugins(cache_key)")
      if err and not (string.find(err, "Column .- was not found in table")       or
                      string.find(err, "[Ii]nvalid column name")                 or
                      string.find(err, "[Uu]ndefined column name")               or
                      string.find(err, "No column definition found for column")  or
                      string.find(err, "Undefined name .- in selection clause")) then
        return nil, err
      end


      _, err = connector:query("CREATE INDEX IF NOT EXISTS ON plugins(run_on)")
      if err and not (string.find(err, "Column .- was not found in table")       or
                      string.find(err, "[Ii]nvalid column name")                 or
                      string.find(err, "[Uu]ndefined column name")               or
                      string.find(err, "No column definition found for column")  or
                      string.find(err, "Undefined name .- in selection clause")) then
        return nil, err
      end


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
          run_on = "text",
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
        run_on = "run_on",
        created_at = "created_at",
        enabled = "enabled",
        cache_key = "cache_key",
      }))

      assert(connector:query("DROP TABLE IF EXISTS plugins_temp"))
      assert(connector:query("DROP TABLE IF EXISTS schema_migrations"))
    end,
  },
}
