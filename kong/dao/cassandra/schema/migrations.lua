local Migrations = {
  -- skeleton
  {
    init = true,
    name = "2015-01-12-175310_skeleton",
    up = function(options)
      return [[
        CREATE KEYSPACE IF NOT EXISTS "]]..options.keyspace..[["
          WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

        USE "]]..options.keyspace..[[";

        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );
      ]]
    end,
    down = function(options)
      return [[
        DROP KEYSPACE "]]..options.keyspace..[[";
      ]]
    end
  },
  -- init schema migration
  {
    name = "2015-01-12-175310_init_schema",
    up = function(options)
      return [[
        CREATE TABLE IF NOT EXISTS consumers(
          id uuid,
          custom_id text,
          username text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON consumers(custom_id);
        CREATE INDEX IF NOT EXISTS ON consumers(username);

        CREATE TABLE IF NOT EXISTS apis(
          id uuid,
          name text,
          public_dns text,
          path text,
          strip_path boolean,
          target_url text,
          preserve_host boolean,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON apis(name);
        CREATE INDEX IF NOT EXISTS ON apis(public_dns);
        CREATE INDEX IF NOT EXISTS ON apis(path);

        CREATE TABLE IF NOT EXISTS plugins_configurations(
          id uuid,
          api_id uuid,
          consumer_id uuid,
          name text,
          value text, -- serialized plugin data
          enabled boolean,
          created_at timestamp,
          PRIMARY KEY (id, name)
        );

        CREATE INDEX IF NOT EXISTS ON plugins_configurations(name);
        CREATE INDEX IF NOT EXISTS ON plugins_configurations(api_id);
        CREATE INDEX IF NOT EXISTS ON plugins_configurations(consumer_id);
      ]]
    end,
    down = function(options)
      return [[
        DROP TABLE consumers;
        DROP TABLE apis;
        DROP TABLE plugins_configurations;
      ]]
    end
  }
}

return Migrations
