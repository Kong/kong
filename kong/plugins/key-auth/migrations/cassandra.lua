return {
  {
    name = "2015-07-31-172400_init_keyauth",
    up =  [[
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id uuid,
        consumer_id uuid,
        key text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(key);
      CREATE INDEX IF NOT EXISTS keyauth_consumer_id ON keyauth_credentials(consumer_id);
    ]],
    down = [[
      DROP TABLE keyauth_credentials;
    ]]
  }
}
