return {
  {
    name = "2015-09-16-132400_init_hmacauth",
    up = [[
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
    ]],
    down = [[
      DROP TABLE hmacauth_credentials;
    ]]
  }
}
