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

      --
      -- NEEDS TO BE RENAMED to avoid confusion
      -- plugins_entries or plugins_configurations
      --
      CREATE TABLE IF NOT EXISTS plugins(
        id uuid,
        api_id uuid,
        application_id uuid,
        name text,
        value text, -- serialized plugin data
        enabled boolean,
        created_at timestamp,
        PRIMARY KEY (id, name)
      );

      CREATE INDEX IF NOT EXISTS ON plugins(name);
      CREATE INDEX IF NOT EXISTS ON plugins(api_id);
      CREATE INDEX IF NOT EXISTS ON plugins(application_id);











































      --
      -- TEMPORARY UNTIL MOVED TO EACH PLUGIN
      -- keyauth_credentials, metrics
      --

      -- username is what the plugin will query this table with. We shouldn't need a consumer_id yet on it
      -- and then compare the password with the one received by a request
      CREATE TABLE IF NOT EXISTS basicauth_credentials(
        consumer_id uuid,
        username text,
        password text,
        created_at timestamp,
        PRIMARY KEY (username, consumer_id)
      );

      -- key is what the plugin will query this table with. We shouldn't need a consumer_id yet on it
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        consumer_id uuid,
        key text,
        created_at timestamp,
        PRIMARY KEY (key, consumer_id)
      );

      CREATE TABLE IF NOT EXISTS ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp,
        value counter,
        PRIMARY KEY ((api_id, identifier, period_date, period))
      );












      --
      -- WILL DISAPEAR, No more applications
      --
      CREATE TABLE IF NOT EXISTS applications(
        id uuid,
        consumer_id uuid,
        public_key text, -- This is the public
        secret_key text, -- This is the secret key, it could be an apikey or basic password
        created_at timestamp,
        PRIMARY KEY (id)
      );
      CREATE INDEX IF NOT EXISTS ON applications(consumer_id);
      CREATE INDEX IF NOT EXISTS ON applications(public_key);
    ]]
  end,

  down = function(options)
    return [[
      DROP KEYSPACE ]]..options.keyspace..[[;

      -- TEMPORARY UNTIL MVOED TO EACH PLUGIN
      DROP TABLE keyauth_credentials;
    ]]
  end
}

return Migration
