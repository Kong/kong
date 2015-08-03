local Migrations = {
  -- init schema migration
  {
    name = "2015-01-12-175310_init_schema",
    init = true,

    up = function(options)
      return [[
        CREATE KEYSPACE IF NOT EXISTS "]]..options.keyspace..[["
          WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

        USE "]]..options.keyspace..[[";

        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );

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
          target_url text,
          preserve_host boolean,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON apis(name);
        CREATE INDEX IF NOT EXISTS ON apis(public_dns);

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
        DROP KEYSPACE "]]..options.keyspace..[[";
      ]]
    end
  },

  -- 0.3.0
  {
    name = "2015-05-22-235608_0.3.0",

    up = function(options)
      return [[
        ALTER TABLE apis ADD path text;
        ALTER TABLE apis ADD strip_path boolean;
        CREATE INDEX IF NOT EXISTS apis_path ON apis(path);
      ]]
    end,

    down = function(options)
      return [[
        DROP INDEX apis_path;
        ALTER TABLE apis DROP path;
        ALTER TABLE apis DROP strip_path;
      ]]
    end
  }
}

return Migrations
