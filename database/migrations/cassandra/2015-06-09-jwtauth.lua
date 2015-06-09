local Migration = {
  name = "2015-06-09-jwtauth",

  up = function(options)
    return [[
      CREATE TABLE IF NOT EXISTS jwtauth_credentials(
        id uuid,
        consumer_id uuid,
        secret text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON jwtauth_credentials(secret);

      CREATE INDEX IF NOT EXISTS jwtauth_consumer_id ON jwtauth_credentials(consumer_id);
    ]]
  end,

  down = function(options)
    return [[
      DROP TABLE jwtauth_credentials;
      DROP INDEX jwtauth_consumer_id;
    ]]
  end
}

return Migration
