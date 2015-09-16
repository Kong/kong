local Migration = {
  {
    name = "2015-06-09-jwt-auth",

    up = function(options)
      return [[
        CREATE TABLE IF NOT EXISTS jwt_secrets(
          id uuid,
          consumer_id uuid,
          key text,
          secret text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON jwt_secrets(key);
        CREATE INDEX IF NOT EXISTS ON jwt_secrets(secret);
        CREATE INDEX IF NOT EXISTS ON jwt_secrets(consumer_id);
      ]]
    end,

    down = function(options)
      return [[
        DROP TABLE jwt_secrets;
      ]]
    end
  }
}

return Migration
