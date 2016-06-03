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
  }
}
