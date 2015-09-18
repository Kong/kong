local Migrations = {
  {
    name = "2015-09-16-132400_init_hmacauth",
    up = function(options)
      return [[
         CREATE TABLE IF NOT EXISTS hmacauth_credentials(
          id uuid,
          consumer_id uuid,
          username text,
          secret text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON hmacauth_credentials(username);
        CREATE INDEX IF NOT EXISTS hmacauth_consumer_id ON hmacauth_credentials(consumer_id);
      ]]
    end,
    down = function(options)
      return [[
        DROP TABLE hmacauth_credentials;
      ]]
    end
  }
}

return Migrations
