local Migrations = {
  {
    name = "2015-07-31-172400_init_keyauth",
    up = function(options, dao_factory)
      return dao_factory:execute_queries [[
        CREATE TABLE IF NOT EXISTS keyauth_credentials(
          id uuid,
          consumer_id uuid,
          key text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON keyauth_credentials(key);
        CREATE INDEX IF NOT EXISTS keyauth_consumer_id ON keyauth_credentials(consumer_id);
      ]]
    end,
    down = function(options, dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE keyauth_credentials;
      ]]
    end
  }
}

return Migrations
