local Migrations = {
  {
    name = "2015-08-03-132400_init_basicauth",
    up = function(options, dao_factory)
      return dao_factory:execute_queries [[
         CREATE TABLE IF NOT EXISTS basicauth_credentials(
          id uuid,
          consumer_id uuid,
          username text,
          password text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON basicauth_credentials(username);
        CREATE INDEX IF NOT EXISTS basicauth_consumer_id ON basicauth_credentials(consumer_id);
      ]]
    end,
    down = function(options, dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE basicauth_credentials;
      ]]
    end
  }
}

return Migrations
