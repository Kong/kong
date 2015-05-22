local Migration = {
  name = "2015-05-22-235608_plugins_fix",

  up = function(options)
    return [[
      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS ON basicauth_credentials(consumer_id);
    ]]
  end,

  down = function(options)
    return [[
      DROP INDEX keyauth_credentials_consumer_id_idx;
      DROP INDEX basicauth_credentials_consumer_id_idx;
    ]]
  end
}

return Migration
