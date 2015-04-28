local Migration = {
  name = "2015-04-24-154530_plugins",

  up = function(options)
    return [[
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
      DROP TABLE basicauth_credentials;
      DROP TABLE keyauth_credentials;
      DROP TABLE ratelimiting_metrics;
    ]]
  end
}

return Migration
