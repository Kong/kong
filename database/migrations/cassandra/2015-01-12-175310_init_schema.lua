local Migration = {
  name = "2015-01-12-175310_init_schema",

  init = true,

  up = function(options)
    return [[
      CREATE KEYSPACE IF NOT EXISTS "]]..options.keyspace..[["
        WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

      USE ]]..options.keyspace..[[;

      CREATE TABLE IF NOT EXISTS schema_migrations(
        id text PRIMARY KEY,
        migrations list<text>
      );

      CREATE TABLE IF NOT EXISTS consumers(
        id uuid,
        custom_id text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON consumers(custom_id);

      CREATE TABLE IF NOT EXISTS apis(
        id uuid,
        name text,
        public_dns text,
        target_url text,
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

      CREATE TABLE IF NOT EXISTS basicauth_credentials(
        id uuid,
        consumer_id uuid,
        username text,
        password text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON basicauth_credentials(username);

      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id uuid,
        consumer_id uuid,
        key text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(key);

      CREATE TABLE IF NOT EXISTS ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp,
        value counter,
        PRIMARY KEY ((api_id, identifier, period_date, period))
      );
    ]]
  end,

  down = function(options)
    return [[
      DROP KEYSPACE ]]..options.keyspace..[[;
    ]]
  end
}

return Migration
