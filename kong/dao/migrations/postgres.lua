return {
  {
    name = "2015-01-12-175310_skeleton",
    up = [[
      CREATE TABLE IF NOT EXISTS schema_migrations(
        id text PRIMARY KEY,
        migrations varchar(100)[]
      );
    ]],
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
        username text,
        created_at timestamp without time zone default (now() at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('public.custom_id_idx')) IS NULL THEN
          CREATE INDEX custom_id_idx ON consumers(custom_id);
        END IF;
        IF (SELECT to_regclass('public.username_idx')) IS NULL THEN
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
        created_at timestamp without time zone default (now() at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('public.apis_name_idx')) IS NULL THEN
          CREATE INDEX apis_name_idx ON apis(name);
        END IF;
        IF (SELECT to_regclass('public.apis_request_host_idx')) IS NULL THEN
          CREATE INDEX apis_request_host_idx ON apis(request_host);
        END IF;
        IF (SELECT to_regclass('public.apis_request_path_idx')) IS NULL THEN
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
        created_at timestamp without time zone default (now() at time zone 'utc'),
        PRIMARY KEY (id, name)
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('public.plugins_name_idx')) IS NULL THEN
          CREATE INDEX plugins_name_idx ON plugins(name);
        END IF;
        IF (SELECT to_regclass('public.plugins_api_idx')) IS NULL THEN
          CREATE INDEX plugins_api_idx ON plugins(api_id);
        END IF;
        IF (SELECT to_regclass('public.plugins_consumer_idx')) IS NULL THEN
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
        created_at timestamp without time zone default (now() at time zone 'utc'),
        PRIMARY KEY (name)
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('public.nodes_cluster_listening_address_idx')) IS NULL THEN
          CREATE INDEX nodes_cluster_listening_address_idx ON nodes(cluster_listening_address);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE nodes;
    ]]
  }

}
