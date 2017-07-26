return {
  {
    name = "2015-01-12-175310_skeleton",
    up = function(db, properties)
      return db:queries [[
        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations varchar(100)[]
        );
      ]]
    end,
    down = [[
      DROP TABLE schema_migrations;
    ]]
  },
  {
    name = "2015-01-12-175310_init_schema",
    up = [[
      CREATE TABLE IF NOT EXISTS consumers(
        id uuid PRIMARY KEY,
        custom_id text,
        username text UNIQUE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('custom_id_idx')) IS NULL THEN
          CREATE INDEX custom_id_idx ON consumers(custom_id);
        END IF;
        IF (SELECT to_regclass('username_idx')) IS NULL THEN
          CREATE INDEX username_idx ON consumers((lower(username)));
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS apis(
        id uuid PRIMARY KEY,
        name text UNIQUE,
        request_host text UNIQUE,
        request_path text UNIQUE,
        strip_request_path boolean NOT NULL,
        upstream_url text,
        preserve_host boolean NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('apis_name_idx')) IS NULL THEN
          CREATE INDEX apis_name_idx ON apis(name);
        END IF;
        IF (SELECT to_regclass('apis_request_host_idx')) IS NULL THEN
          CREATE INDEX apis_request_host_idx ON apis(request_host);
        END IF;
        IF (SELECT to_regclass('apis_request_path_idx')) IS NULL THEN
          CREATE INDEX apis_request_path_idx ON apis(request_path);
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS plugins(
        id uuid,
        name text NOT NULL,
        api_id uuid REFERENCES apis(id) ON DELETE CASCADE,
        consumer_id uuid REFERENCES consumers(id) ON DELETE CASCADE,
        config json NOT NULL,
        enabled boolean NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id, name)
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('plugins_name_idx')) IS NULL THEN
          CREATE INDEX plugins_name_idx ON plugins(name);
        END IF;
        IF (SELECT to_regclass('plugins_api_idx')) IS NULL THEN
          CREATE INDEX plugins_api_idx ON plugins(api_id);
        END IF;
        IF (SELECT to_regclass('plugins_consumer_idx')) IS NULL THEN
          CREATE INDEX plugins_consumer_idx ON plugins(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE consumers;
      DROP TABLE apis;
      DROP TABLE plugins;
    ]]
  },
  {
    name = "2015-11-23-817313_nodes",
    up = [[
      CREATE TABLE IF NOT EXISTS nodes(
        name text,
        cluster_listening_address text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (name)
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('nodes_cluster_listening_address_idx')) IS NULL THEN
          CREATE INDEX nodes_cluster_listening_address_idx ON nodes(cluster_listening_address);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE nodes;
    ]]
  },
  {
    name = "2016-02-29-142793_ttls",
    up = [[
      CREATE TABLE IF NOT EXISTS ttls(
        primary_key_value text NOT NULL,
        primary_uuid_value uuid,
        table_name text NOT NULL,
        primary_key_name text NOT NULL,
        expire_at timestamp without time zone NOT NULL,
        PRIMARY KEY(primary_key_value, table_name)
      );

      CREATE OR REPLACE FUNCTION upsert_ttl(v_primary_key_value text, v_primary_uuid_value uuid, v_primary_key_name text, v_table_name text, v_expire_at timestamp) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE ttls SET expire_at = v_expire_at WHERE primary_key_value = v_primary_key_value AND table_name = v_table_name;
          IF found then
            RETURN;
          END IF;
          BEGIN
            INSERT INTO ttls(primary_key_value, primary_uuid_value, primary_key_name, table_name, expire_at) VALUES(v_primary_key_value, v_primary_uuid_value, v_primary_key_name, v_table_name, v_expire_at);
            RETURN;
          EXCEPTION WHEN unique_violation THEN
            -- Do nothing, and loop to try the UPDATE again.
          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = [[
      DROP TABLE ttls;
      DROP FUNCTION upsert_ttl(text, uuid, text, text, timestamp);
    ]]
  },
  {
    name = "2016-09-05-212515_retries",
    up = [[
      DO $$
      BEGIN
        ALTER TABLE apis ADD COLUMN retries smallint;
        ALTER TABLE apis ALTER COLUMN retries SET DEFAULT 5;
        UPDATE apis SET retries = 5;
      EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
      END$$;
    ]],
    down = [[
      ALTER TABLE apis DROP COLUMN IF EXISTS retries;
    ]]
  },
  {
    name = "2016-09-16-141423_upstreams",
    -- Note on the timestamps below; these use a precision of milliseconds
    -- this differs from the other tables above, as they only use second precision.
    -- This differs from the change to the Cassandra entities.
    up = [[
      CREATE TABLE IF NOT EXISTS upstreams(
        id uuid PRIMARY KEY,
        name text UNIQUE,
        slots int NOT NULL,
        orderlist text NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('upstreams_name_idx')) IS NULL THEN
          CREATE INDEX upstreams_name_idx ON upstreams(name);
        END IF;
      END$$;
      CREATE TABLE IF NOT EXISTS targets(
        id uuid PRIMARY KEY,
        target text NOT NULL,
        weight int NOT NULL,
        upstream_id uuid REFERENCES upstreams(id) ON DELETE CASCADE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('targets_target_idx')) IS NULL THEN
          CREATE INDEX targets_target_idx ON targets(target);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE upstreams;
      DROP TABLE targets;
    ]],
  },
  {
    name = "2016-12-14-172100_move_ssl_certs_to_core",
    up = [[
      CREATE TABLE ssl_certificates(
        id uuid PRIMARY KEY,
        cert text ,
        key text ,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE TABLE ssl_servers_names(
        name text PRIMARY KEY,
        ssl_certificate_id uuid REFERENCES ssl_certificates(id) ON DELETE CASCADE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      ALTER TABLE apis ADD https_only boolean;
      ALTER TABLE apis ADD http_if_terminated boolean;
    ]],
    down = [[
      DROP TABLE ssl_certificates;
      DROP TABLE ssl_servers_names;

      ALTER TABLE apis DROP COLUMN IF EXISTS https_only;
      ALTER TABLE apis DROP COLUMN IF EXISTS http_if_terminated;
    ]]
  },
  {
    name = "2016-11-11-151900_new_apis_router_1",
    up = [[
      DO $$
      BEGIN
        ALTER TABLE apis ADD hosts text;
        ALTER TABLE apis ADD uris text;
        ALTER TABLE apis ADD methods text;
        ALTER TABLE apis ADD strip_uri boolean;
      EXCEPTION WHEN duplicate_column THEN

      END$$;
    ]],
    down = [[
      ALTER TABLE apis DROP COLUMN IF EXISTS hosts;
      ALTER TABLE apis DROP COLUMN IF EXISTS uris;
      ALTER TABLE apis DROP COLUMN IF EXISTS methods;
      ALTER TABLE apis DROP COLUMN IF EXISTS strip_uri;
    ]]
  },
  {
    name = "2016-11-11-151900_new_apis_router_2",
    up = function(_, _, dao)
      -- create request_headers and request_uris
      -- with one entry each: the current request_host
      -- and the current request_path
      -- We use a raw SQL query because we removed the
      -- request_host/request_path fields in the API schema,
      -- hence the Postgres DAO won't include them in the
      -- retrieved rows.
      local rows, err = dao.db:query([[
        SELECT * FROM apis;
      ]])
      if err then
        return err
      end

      local fmt = string.format
      local cjson = require("cjson")

      for _, row in ipairs(rows) do
        local set = {}

        local upstream_url = row.upstream_url
        while string.sub(upstream_url, #upstream_url) == "/" do
          upstream_url = string.sub(upstream_url, 1, #upstream_url - 1)
        end
        set[#set + 1] = fmt("upstream_url = '%s'", upstream_url)

        if row.request_host and row.request_host ~= "" then
          set[#set + 1] = fmt("hosts = '%s'", 
                              cjson.encode({ row.request_host }))
        end

        if row.request_path and row.request_path ~= "" then
          set[#set + 1] = fmt("uris = '%s'", 
                              cjson.encode({ row.request_path }))
        end

        set[#set + 1] = fmt("strip_uri = %s", tostring(row.strip_request_path))

        if #set > 0 then
          local query = [[UPDATE apis SET %s WHERE id = '%s';]]
          local _, err = dao.db:query(
            fmt(query, table.concat(set, ", "), row.id)
          )
          if err then
            return err
          end
        end
      end
    end,
    down = function(_, _, dao)
      -- re insert request_host and request_path from
      -- the first element of request_headers and
      -- request_uris

    end
  },
  {
    name = "2016-11-11-151900_new_apis_router_3",
    up = [[
      DROP INDEX IF EXISTS apis_request_host_idx;
      DROP INDEX IF EXISTS apis_request_path_idx;

      ALTER TABLE apis DROP COLUMN IF EXISTS request_host;
      ALTER TABLE apis DROP COLUMN IF EXISTS request_path;
      ALTER TABLE apis DROP COLUMN IF EXISTS strip_request_path;
    ]],
    down = [[
      ALTER TABLE apis ADD request_host text;
      ALTER TABLE apis ADD request_path text;
      ALTER TABLE apis ADD strip_request_path boolean;

      CREATE INDEX IF NOT EXISTS ON apis(request_host);
      CREATE INDEX IF NOT EXISTS ON apis(request_path);
    ]]
  },
  {
    name = "2016-01-25-103600_unique_custom_id",
    up = [[
      ALTER TABLE consumers ADD CONSTRAINT consumers_custom_id_key UNIQUE(custom_id);
    ]],
    down = [[
      ALTER TABLE consumers DROP CONSTRAINT consumers_custom_id_key;
    ]],
  },
  {
    name = "2017-01-24-132600_upstream_timeouts",
    up = [[
      ALTER TABLE apis ADD upstream_connect_timeout integer;
      ALTER TABLE apis ADD upstream_send_timeout integer;
      ALTER TABLE apis ADD upstream_read_timeout integer;
    ]],
    down = [[
      ALTER TABLE apis DROP COLUMN IF EXISTS upstream_connect_timeout;
      ALTER TABLE apis DROP COLUMN IF EXISTS upstream_send_timeout;
      ALTER TABLE apis DROP COLUMN IF EXISTS upstream_read_timeout;
    ]]
  },
  {
    name = "2017-01-24-132600_upstream_timeouts_2",
    up = function(_, _, dao)
      local rows, err = dao.db:query([[
        SELECT * FROM apis;
      ]])
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        if not row.upstream_connect_timeout
          or not row.upstream_read_timeout
          or not row.upstream_send_timeout then

          local _, err = dao.apis:update({
            upstream_connect_timeout = 60000,
            upstream_send_timeout = 60000,
            upstream_read_timeout = 60000,
          }, { id = row.id })
          if err then
            return err
          end
        end
      end
    end,
    down = function(_, _, dao) end
  },
  {
    name = "2017-03-27-132300_anonymous",
    -- this should have been in 0.10, but instead goes into 0.10.1 as a bugfix
    up = function(_, _, dao)
      for _, name in ipairs({
        "basic-auth",
        "hmac-auth",
        "jwt",
        "key-auth",
        "ldap-auth",
        "oauth2",
      }) do
        local rows, err = dao.plugins:find_all( { name = name } )
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          if not row.config.anonymous then
            row.config.anonymous = ""
            local _, err = dao.plugins:update(row, { id = row.id })
            if err then
              return err
            end
          end
        end
      end
    end,
    down = function(_, _, dao) end
  },
  {
    name = "2017-04-18-153000_unique_plugins_id",
    up = function(_, _, dao)
      local duplicates, err = dao.db:query([[
        SELECT plugins.*
        FROM plugins
        JOIN (
          SELECT id
          FROM plugins
          GROUP BY id
          HAVING COUNT(1) > 1)
        AS x
        USING (id)
        ORDER BY id, name;
      ]])
      if err then
        return err
      end

      -- we didnt find any duplicates; we're golden!
      if #duplicates == 0 then
        return
      end

      -- print a human-readable output of all the plugins with conflicting ids
      local t = {}
      t[#t + 1] = "\n\nPlease correct the following duplicate plugin entries and re-run this migration:\n"
      for i = 1, #duplicates do
        local d = duplicates[i]
        local p = {}
        for k, v in pairs(d) do
          p[#p + 1] = k .. ": " .. tostring(v)
        end
        t[#t + 1] = table.concat(p, "\n")
        t[#t + 1] = "\n"
      end

      return table.concat(t, "\n")
    end,
    down = function(_, _, dao) return end
  },
  {
    name = "2017-04-18-153000_unique_plugins_id_2",
    up = [[
      ALTER TABLE plugins ADD CONSTRAINT plugins_id_key UNIQUE(id);
    ]],
    down = [[
      ALTER TABLE plugins DROP CONSTRAINT plugins_id_key;
    ]],
  },
  {
    name = "2017-05-19-180200_cluster_events",
    up = [[
      CREATE TABLE IF NOT EXISTS cluster_events (
          id uuid NOT NULL,
          node_id uuid NOT NULL,
          at TIMESTAMP WITH TIME ZONE NOT NULL,
          nbf TIMESTAMP WITH TIME ZONE,
          expire_at TIMESTAMP WITH TIME ZONE NOT NULL,
          channel text,
          data text,
          PRIMARY KEY (id)
      );

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_cluster_events_at')) IS NULL THEN
              CREATE INDEX idx_cluster_events_at ON cluster_events (at);
          END IF;
          IF (SELECT to_regclass('idx_cluster_events_channel')) IS NULL THEN
              CREATE INDEX idx_cluster_events_channel ON cluster_events (channel);
          END IF;
      END$$;

      CREATE OR REPLACE FUNCTION delete_expired_cluster_events() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
          DELETE FROM cluster_events WHERE expire_at <= NOW();
          RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
          IF NOT EXISTS(
              SELECT FROM information_schema.triggers
               WHERE event_object_table = 'cluster_events'
                 AND trigger_name = 'delete_expired_cluster_events_trigger')
          THEN
              CREATE TRIGGER delete_expired_cluster_events_trigger
               AFTER INSERT ON cluster_events
               EXECUTE PROCEDURE delete_expired_cluster_events();
          END IF;
      END;
      $$;
    ]],
    down = [[
      DROP TABLE IF EXISTS cluster_events;
      DROP FUNCTION IF EXISTS delete_expired_cluster_events;
      DROP TRIGGER IF EXISTS delete_expired_cluster_events_trigger;
    ]],
  },
  {
    name = "2017-05-19-173100_remove_nodes_table",
    up = [[
      DELETE FROM ttls WHERE table_name = 'nodes';

      DROP TABLE nodes;
    ]],
  },
  {
    name = "2017-06-16-283123_ttl_indexes",
    up = [[
      DO $$
      BEGIN
        IF (SELECT to_regclass('ttls_primary_uuid_value_idx')) IS NULL THEN
          CREATE INDEX ttls_primary_uuid_value_idx ON ttls(primary_uuid_value);
        END IF;
      END$$;
    ]],
    down = [[
      DROP INDEX ttls_primary_uuid_value_idx;
    ]]
  },
}
