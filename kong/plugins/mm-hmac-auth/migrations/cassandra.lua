local Migrations = {
  {
    name = "2015-09-21-132400_init_mm_hmacauth",
    up = function(options)
      return [[
         CREATE TABLE IF NOT EXISTS mm_hmacauth_credentials(
          id uuid,
          consumer_id uuid,
          username text,
          secret text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON mm_hmacauth_credentials(username);
        CREATE INDEX IF NOT EXISTS mm_hmacauth_consumer_id ON mm_hmacauth_credentials(consumer_id);
      ]]
    end,
    down = function(options)
      return [[
        DROP TABLE mm_hmacauth_credentials;
      ]]
    end
  }
}

return Migrations
