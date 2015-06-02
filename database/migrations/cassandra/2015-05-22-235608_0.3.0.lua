local Migration = {
  name = "2015-05-22-235608_0.3.0",

  up = function(options)
    return [[
      CREATE INDEX IF NOT EXISTS keyauth_consumer_id ON keyauth_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS basicauth_consumer_id ON basicauth_credentials(consumer_id);

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

      DROP INDEX keyauth_consumer_id;
      DROP INDEX basicauth_consumer_id;
    ]]
  end
}

return Migration
