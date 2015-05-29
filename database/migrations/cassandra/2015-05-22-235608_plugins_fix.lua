local Migration = {
  name = "2015-05-22-235608_plugins_fix",

  up = function(options)
    return [[
      CREATE INDEX IF NOT EXISTS keyauth_consumer_id ON keyauth_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS basicauth_consumer_id ON basicauth_credentials(consumer_id);
    ]]
  end,

  down = function(options)
    return [[
      DROP INDEX keyauth_consumer_id;
      DROP INDEX basicauth_consumer_id;
    ]]
  end
}

return Migration
