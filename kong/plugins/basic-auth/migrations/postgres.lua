return {
  {
    name = "2015-08-03-132400_init_basicauth",
    up = [[
      CREATE TABLE IF NOT EXISTS basicauth_credentials(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        username text,
        password text,
        created_at timestamp without time zone default (now() at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('public.basicauth_username_idx')) IS NULL THEN
          CREATE INDEX basicauth_username_idx ON basicauth_credentials(username);
        END IF;
        IF (SELECT to_regclass('public.basicauth_consumer_id_idx')) IS NULL THEN
          CREATE INDEX basicauth_consumer_id_idx ON basicauth_credentials(consumer_id);
        END IF;
      END$$;
    ]],
    down =  [[
      DROP TABLE basicauth_credentials;
    ]]
  }
}
