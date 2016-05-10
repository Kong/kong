return {
  {
    name = "2015-09-16-132400_init_hmacauth",
    up = [[
       CREATE TABLE IF NOT EXISTS hmacauth_credentials(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        username text UNIQUE,
        secret text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('hmacauth_credentials_username')) IS NULL THEN
          CREATE INDEX hmacauth_credentials_username ON hmacauth_credentials(username);
        END IF;
        IF (SELECT to_regclass('hmacauth_credentials_consumer_id')) IS NULL THEN
          CREATE INDEX hmacauth_credentials_consumer_id ON hmacauth_credentials(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE hmacauth_credentials;
    ]]
  }
}
